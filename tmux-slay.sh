#!/usr/bin/env bash

usage() {
  echo "Usage: $(basename "$0") run|kill|check|list [CMD]"
}

check_session() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null | \
    grep -qE -- "^${TMUX_SLAY_SESSION}\$"
}

create_session() {
  local args=(new-session -d -s "$TMUX_SLAY_SESSION" -n "$TMUX_SLAY_INIT_WINDOW_TITLE")
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  export XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"
  local tmux_config=${XDG_CONFIG_HOME}/tmux/tmux.conf

  # Apply XDG_CONFIG_HOME hack
  if [[ -r "$tmux_config" ]]
  then
    args=(-f "$tmux_config" "${args[@]}")
  fi

  # Create session
  tmux "${args[@]}"

  # Disable destroy-unattached for this session
  tmux -f "$tmux_config" set-option -t "$TMUX_SLAY_SESSION" \
    destroy-unattached off
}

list_commands() {
  local cmd
  local output
  local pane_id
  local raw
  local simple
  local window_name

  while [[ -n "$*" ]]
  do
    case "$1" in
      -r|--raw)
        raw=1
        shift
        ;;
      -s|--simple)
        simple=1
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  tmux list-panes -s -t "$TMUX_SLAY_SESSION" \
      -F '#{pane_id} #{pane_start_command}' \
      2>/dev/null | \
    while read -r output
  do
    # Check if a command filter has been provided
    if [[ -n "$*" ]] && ! grep -q -- "$*" <<< "$output"
    then
      continue
    fi

    # Only display panes with a non-empty start command
    if [[ "$(wc -w <<< "$output")" -lt 2 ]]
    then
      continue
    fi

    read -r pane_id cmd <<< "$output"
    window_name="$(tmux_get_window_name_from_pane_id "$pane_id")"

    if [[ -n "$raw" ]]
    then
      echo "$pane_id $window_name $cmd"
    else
      local fcmd
      local ogcmd

      read -r pane_id cmd <<< "$output"
      fcmd="$(filter_out_metadata "$cmd")"
      ogcmd="$(extract_slay_og_cmd "$cmd")"

      if [[ -n "$simple" ]]
      then
        echo "$pane_id [${window_name}] $ogcmd"
      else
        echo "$pane_id [${window_name}] $ogcmd [$fcmd]"
      fi
    fi
  done
}

guess_window_id_from_input() {
  local nofallback

  case "$1" in
    -n|--no-guess|--no-last|--no-fallback)
      nofallback=1
      shift
      ;;
  esac

  if [[ -z "$1" ]] && [[ -z "$nofallback" ]]
  then
    # No param. Get the last pane (previous command)
    get_latest_window
    # Alternative that will select the last window (by window index):
    # tmux_get_last_window_id
  elif [[ "$1" =~ ^[+-]?[0-9]+([.][0-9]+)?$ ]]
  then
    mapfile -t win_ids < <(tmux_get_all_window_ids | sort)
    echo "${win_ids[$1]}" 2>/dev/null
  elif [[ "$1" =~ %.+ ]]
  then
    # Pane ID provided
    tmux_get_window_id_from_pane_id "$1"
  elif [[ "$1" =~ @.+ ]]
  then
    # Window ID provided
    echo -- "$@"
  else
    # Command provided
    get_cmd_window_id "$@"
  fi
}

select_window() {
  local id

  id="$(guess_window_id_from_input "$@")"

  if [[ -n "$id" ]]
  then
    # Focus session
    tmux switch-client -t "${TMUX_SLAY_SESSION}"
    # Focus window
    tmux select-window -t "${TMUX_SLAY_SESSION}:${id}"
  else
    return 1
  fi
}

check_on_command() {
  [[ -n "$(get_cmd_window_id "$@")" ]]
}

slugify_cmd_human() {
  sed -r 's/[^a-zA-Z0-9]+/-/g' <<< "$@" | \
    sed -r 's/^-+\|-+$//g' | \
    tr '[:upper:]' '[:lower:]' | \
    cut -c 1-20
}

slugify_cmd_machine() {
  md5sum <<< "$@" | awk '{ print $1 }'
}

wrap_command() {
  local wcmd="$*"
  local wait_period="${WAIT_PERIOD:-1}"
  local tshell="${SLAY_SHELL:-zsh -ic}"
  local sudocmd="${SLAY_SUDO:-sudo --}"
  local noid

  case "$1" in
    -n|--no-id)
      noid=1
      shift
      ;;
  esac

  if [[ -n "$TIMEOUT" ]]
  then
    wcmd="timeout -k ${TIMEOUT}s -s 9 ${TIMEOUT}s $tshell '${wcmd}'"
  fi

  if [[ -n "$LOOP" ]]
  then
    wcmd="while true; do ${wcmd}; sleep ${wait_period}; done"
  fi

  if [[ -z "$NOWRAP" ]]
  then
    wcmd="$tshell "\"${wcmd}\"""
  fi

  if [[ -n "$SUDO" ]]
  then
    # FIXME The "\\" leads to the command in list containing \ chars
    # Example: %204 sudo -- \while true; do whoami; sleep 1; done\
    # wcmd="sudo -- \\"${wcmd}\\""
    wcmd="$sudocmd \\"${wcmd}\\""
  fi

  if [[ -n "$TMUX_SLAY_DEBUG" ]]
  then
    echo "Wrapped command: $wcmd" >&2
  fi

  if [[ -n "$noid" ]]
  then
    echo "$wcmd"
  else
    echo -n "$wcmd "
    echo -n "# SLAY_CMD_ID='$(slugify_cmd_machine "$@")' "
    echo -n "# SLAY_DATE='$(date -Iseconds)' "
    echo -n "# SLAY_OG_CMD='${*}' "
    {
      echo -n "# SLAY_PARAMS='"
      echo -n "LOOP=\"${LOOP}\" "
      echo -n "WAIT_PERIOD=\"${wait_period}\" "
      echo -n "SUDO=\"${SUDO}\" "
      echo -n "SUDO_CMD=\"${sudocmd}\" "
      echo -n "SLAY_SHELL=\"${tshell}\" "
      echo -n "TIMEOUT=\"${TIMEOUT}\""
      printf "'\n"
    }
  fi
}

extract_slay_cmd_id() {
  sed -nr "s/.*SLAY_CMD_ID='([a-z0-9]+)'.*/\1/p" <<< "$*"
}

extract_slay_og_cmd() {
  sed -nr "s/.*SLAY_OG_CMD='(.+)' # SLAY_.*/\1/p" <<< "$*"
}

extract_slay_params() {
  sed -nr "s/.*SLAY_PARAMS='([^']+)'.*/\1/p" <<< "$*"
}

extract_slay_date() {
  sed -nr "s/.*SLAY_DATE='([^']+)'.*/\1/p" <<< "$*"
}

get_slay_param() {
  # Usage: get_slay_param WAIT_PERIOD "$(list_commands -r | head -1)"
  # shellcheck disable=2034
  {
    local LOOP
    local WAIT_PERIOD
    local SUDO
    local SUDO_CMD
    local SLAY_SHELL
  }

  local requested_param="$1"
  shift

  eval "$(extract_slay_params "$@")"

  eval "echo \$$requested_param"
}

filter_out_metadata() {
  sed -rn 's/(.+) # SLAY_CMD_ID=.+$/\1/p' <<< "$*" | \
    sed 's#\\##g'
  # NOTE the sed 's#\\##g' is to unfuck the display of sudo commands
  # Example: %204 test sudo -- \while true; do whoami; sleep 1; done\
}

list_slay_cmd_ids() {
  local output
  output="$(list_commands -r)"
  extract_slay_cmd_id "$output"
}

tmux_exec() {
  local name="$1"
  shift
  local target_window="$TMUX_SLAY_SESSION"

  local extra_args=()

  if [[ -n "$BACKGROUND" ]]
  then
    extra_args+=(-d)
  fi

  if [[ -n "$TMUX_SLAY_CWD" ]]
  then
    extra_args+=(-c "$TMUX_SLAY_CWD")
  fi

  if [[ -n "$APPEND" ]]
  then
    extra_args+=(-a)
  else
    target_window+=":$(tmux_get_next_available_window_index)"
  fi

  if [[ -n "${SLAY_ENV[*]}" ]]
  then
    local e
    for e in "${SLAY_ENV[@]}"
    do
      extra_args+=(-e "$e")
    done
  fi

  tmux new-window -t "$target_window" -n "$name" \
    "${extra_args[@]}" -- "$@"
}

tmux_exec_wrap() {
  local cmd
  local name

  case "$1" in
    -n|--name)
      if [[ -n "$2" ]]
      then
        name="$2"
      fi
      shift 2
      ;;
  esac

  if [[ -z "$name" ]]
  then
    name="$(slugify_cmd_human "$@")"
  fi

  cmd="$(wrap_command "$@")"
  tmux_exec "$name" "$cmd"
}

tmux_window_exists() {
  tmux list-windows -t "$TMUX_SLAY_SESSION" -F '#{window_name}' | \
    grep -qE -- "^${1}\$"
}

tmux_get_all_windows() {
  # Filter out TMUX_SLAY_INIT_WINDOW_TITLE so that we do not kill the session
  tmux list-windows -t "$TMUX_SLAY_SESSION" \
    -F '#{window_id} #{window_name}' 2>/dev/null | \
      grep -v -- "$TMUX_SLAY_INIT_WINDOW_TITLE"
}

tmux_get_all_window_ids() {
  tmux_get_all_windows | awk '{ print $1 }'
}

tmux_get_last_window_id() {
  tmux_get_all_windows | head -1 | awk '{ print $1 }'
}

get_latest_window() {
  local cmd
  local current_pane_id
  local output
  local pane_id
  local start_date
  local tmp
  local ts=-1

  while read -r output
  do
    read -r current_pane_id _ cmd <<< "$output"
    start_date="$(extract_slay_date "$cmd")"
    tmp="$(date -d "$start_date" +'%s')"

    if [[ "$tmp" -gt "$ts" ]]
    then
      ts="$tmp"
      pane_id="$current_pane_id"
    fi
  done < <(list_commands -r)

  if [[ -n "$pane_id" ]]
  then
    tmux_get_window_id_from_pane_id "$pane_id"
  fi
}

tmux_get_window_info() {
  tmux list-windows -t "$TMUX_SLAY_SESSION" \
    -F '#{window_id} #{window_name}' | \
    grep -- "$1"
}

tmux_get_last_window_index() {
  tmux list-windows -t "$TMUX_SLAY_SESSION" -F '#{window_index}' | \
    sort -u | tail -1
}

tmux_get_next_available_window_index() {
  local last_win_index
  last_win_index="$(tmux_get_last_window_index)"
  echo $(( last_win_index + 1 ))
}

tmux_get_window_id_from_window_name() {
  tmux_get_window_info "$1"| awk '{ print $1 }'
}

tmux_get_window_name_from_window_id() {
  tmux_get_window_info "$1" | awk '{ print $2 }'
}

tmux_get_window_info_from_pane_id() {
  tmux list-panes -s -t "$TMUX_SLAY_SESSION" \
    -F '#{pane_id} #{window_id} #{window_name}' | \
    grep -- "$1"
}

tmux_get_window_id_from_pane_id() {
  tmux_get_window_info_from_pane_id "$1" | awk '{ print $2 }'
}

tmux_get_window_name_from_pane_id() {
  tmux_get_window_info_from_pane_id "$1" | awk '{ print $3 }'
}

get_cmd_window_id() {
  local current
  local og_cmd
  local pane_id

  list_commands -r | while read -r current
  do
    og_cmd="$(extract_slay_og_cmd "$current")"
    if [[ -n "$TMUX_SLAY_DEBUG" ]]
    then
      echo "CMD=$* vs. OG_CMD=$og_cmd" >&2
    fi
    if [[ "$og_cmd" == "$*" ]]
    then
      pane_id="$(awk '{ print $1 }' <<< "$current")"
      tmux_get_window_id_from_pane_id "$pane_id"
    fi
  done
}

_tmux_kill_windows() {
  local -a win_ids=("$@")
  local win_id
  local win_name

  if [[ -z "${win_ids[*]}" ]]
  then
    return 1
  fi

  for win_id in "${win_ids[@]}"
  do
    # _tmux_kill_window "$win_id"
    win_name="$(tmux_get_window_name_from_window_id "$win_id")"
    echo "Killing window $win_name"
    tmux kill-window -t "${TMUX_SLAY_SESSION}:${win_id}"
  done
}

tmux_kill_window() {
  local -a win_ids
  local win_name
  local input_type

  case "$1" in
    --all|-a)
      input_type=all
      shift
      ;;
    --latest|-l)
      input_type=latest
      shift
      ;;
    --cmd|-c)
      input_type=cmd
      shift
      ;;
    --guess|-g)
      input_type=guess
      shift
      ;;
    --pane-id|--pane|-p)
      input_type=pane_id
      shift
      ;;
    --window-id|--wid|--id)
      input_type=window_id
      shift
      ;;
    --window-name|--name|-n)
      input_type=window_name
      shift
      ;;
    *)
      input_type=guess
      ;;
  esac

  case "$input_type" in
    all)
      mapfile -t win_ids < <(tmux_get_all_window_ids)
      ;;
    latest)
      mapfile -t win_ids < <(get_latest_window)
      ;;
    cmd)
      mapfile -t win_ids < <(get_cmd_window_id "$@")
      ;;
    pane_id)
      mapfile -t win_ids < <(tmux_get_window_id_from_pane_id "$@")
      ;;
    window_id)
      win_ids=("$@")
      ;;
    window_name)
      # Window name provided
      mapfile -t win_ids < <(tmux_get_window_id_from_window_name "$@")
      ;;
    guess)
      mapfile -t win_ids < <(guess_window_id_from_input -n "$@")
      ;;
  esac

  if [[ -z "${win_ids[*]}" ]]
  then
    return 1
  fi

  _tmux_kill_windows "${win_ids[@]}"
}

# Parameters (global env vars)
TMUX_SLAY_DEBUG=${TMUX_SLAY_DEBUG} # Set to any var to enable debug mode
TMUX_SLAY_SESSION="${TMUX_SLAY_SESSION:-bg}"
TMUX_SLAY_INIT_WINDOW_TITLE="${TMUX_SLAY_INIT_WINDOW_TITLE:-bg-init}"


if [[ "${BASH_SOURCE[0]}" == "${0}" ]]
then
  set -e

  SLAY_ENV=()

  case "$1" in
    help|h|--help|-h)
      usage
      exit 0
      ;;
    run|start|r|s|up)
      ACTION=run
      shift
      while [[ -n "$*" ]]
      do
        case "$1" in
          -a|--append)
            APPEND=1
            shift
            ;;
          -u|--unique)
            UNIQUE=1
            shift
            ;;
          -c|--check)
            CHECK=1
            shift
            ;;
          -k|--kill)
            # shellcheck disable=2209
            ACTION=kill
            shift
            ;;
          -N|-W|--nowrap|--no-wrap)
            NOWRAP=1
            shift
            ;;
          --cd|--cwd)
            TMUX_SLAY_CWD="$2"
            shift 2
            ;;
          -n|--name)
            NAME="$2"
            shift 2
            ;;
          -l|--loop)
            LOOP=1
            # Check if $2 is a positive integer
            # https://stackoverflow.com/a/808740/1872036
            if [[ -n "$2" ]] && [[ "$2" -eq "$2" ]] 2>/dev/null && [[ "$2" -gt 0 ]]
            then
              WAIT_PERIOD="$2"
              shift
            fi
            shift
            ;;
          -w|--wait)
            WAIT_PERIOD="$2"
            shift 2
            ;;
          -s|--sudo)
            SUDO=1
            shift
            ;;
          -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
          -f|--foreground|-S|--select)
            SELECT=1
            shift
            ;;
          -b|--background)
            BACKGROUND=1
            shift
            ;;
          -e|--env)
            SLAY_ENV+=("$2")
            shift 2
            ;;
          -q|--quiet)
            QUIET=1
            shift
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done
      if [[ -n "$TMUX_SLAY_DEBUG" ]]
      then
        {
          echo -n "LOOP=$LOOP UNIQUE=$UNIQUE CHECK=$CHECK KILL=$KILL "
          echo "ACTION=$ACTION WAIT_PERIOD=$WAIT_PERIOD"
          echo "SLAY_ENV=${SLAY_ENV[*]}"
          echo "CMD=$*"
        } >&2
      fi
      ;;
    kill|stop|k|down)
      # shellcheck disable=2209
      ACTION=kill
      shift
      while [[ -n "$*" ]]
      do
        case "$1" in
          -n|--name)
            NAME="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done
      ;;
    clean|killall)
      ACTION=killall
      shift
      while [[ -n "$*" ]]
      do
        case "$1" in
          -n|--name)
            NAME="$2"
            shift 2
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done
      ;;
    check)
      ACTION=check
      shift
      while [[ -n "$*" ]]
      do
        case "$1" in
          -q|--quiet)
            QUIET=1
            shift
            ;;
          --)
            shift
            break
            ;;
          *)
            break
            ;;
        esac
      done
      ;;
    list|ls)
      ACTION=list
      shift
      ;;
    select|show)
      ACTION=select
      shift
      ;;
    *)
      usage
      exit 2
      ;;
  esac

  case "$ACTION" in
    list)
      list_commands "$@" | sort
      ;;
    select)
      select_window "$@"
      ;;
    check)
      if [[ -z "$*" ]]
      then
        echo "Missing command." >&2
        exit 2
      fi
      if check_on_command "$@"
      then
        if [[ -z "$QUIET" ]]
        then
          list_commands -s "$@"
        fi
        exit 0
      else
        if [[ -z "$QUIET" ]]
        then
          echo "Command $* is NOT running." >&2
        fi
        exit 1
      fi
      ;;
    run)
      if [[ -z "$*" ]]
      then
        echo "Missing command." >&2
        exit 2
      fi

      if ! check_session
      then
        create_session
      fi

      # If CHECK is set then don't re-execute the command if it is already running
      if [[ "$CHECK" == "1" ]] && check_on_command "$@"
      then
        if [[ -z "$QUIET" ]]
        then
          list_commands -s "$@"
        fi
        if [[ -n "$SELECT" ]]
        then
          select_window "$@"
        fi
        exit 0
      fi

      # Kill previous commands if UNIQUE
      if [[ "$UNIQUE" == "1" ]]
      then
        # TODO Kill all except latest
        tmux_kill_window --cmd "$@" || true
      fi

      tmux_exec_wrap -n "$NAME" "$@"
      list_commands -s "$@"

      if [[ -n "$SELECT" ]]
      then
        select_window "$@"
      fi
      ;;
    kill)
      if [[ -n "$NAME" ]]
      then
        tmux_kill_window --name "$NAME"
      else
        if [[ -n "$*" ]]
        then
          tmux_kill_window "$@"
        else
          tmux_kill_window --latest
        fi
      fi
      ;;
    killall)
      if [[ -n "$NAME" ]]
      then
        tmux_kill_window --name "$NAME"
      elif [[ -n "$*" ]]
      then
        tmux_kill_window "$@"
      else
        tmux_kill_window --all
      fi
      ;;
  esac
fi

# vim: set ft=bash et ts=2 sw=2 :