# 🚬 tmux-slay

This scripts allows running commands in the background, in a TMUX session.

It can be a poor man's init-sytem.

# 🚏 Dependencies

bash, awk, sed and tmux 🤷‍♂️

# 🔨 Installation

## 🧊 Using zinit

```zsh
zinit light-mode wait lucid as"null" \
  sbin"tmux-slay" \
  atload"alias tslay=tmux-slay" \
  for @pschmitt/tmux-slay
```

## 🦆 Otherwise

Just get `tmux-slay` and put it in your PATH.

# 🎼 Completions

Completions for ZSH are available in the `completions/` dir.

# 🎮 Usage

```bash
# Run single command
tmux-slay run COMMAND

# List running commands
tmux-slay list

# Display and follow log
tmux-slay logs -f COMMAND

# Stop/kill it
tmux-slay kill COMMAND

# Run command in a loop (repeatedly)
tmux-slay run -l COMMAND

# Run command once (don't start a second instance if it is already running)
tmux-slay run -c COMMAND

# Spawn a new instance of COMMAND and kill other windows running the same command
tmux-slay run -u COMMAND

# Clear all. Kill all running commands
tmux-slay killall

# Focus on output window running command
tmux-slay select COMMAND
```

# ⚙️ Configuration

## 👶 Session name

By default `tmux-slay` will create a new TMUX session named `bg` (for
backgroud) to run all the commands you instruct it to.

To change that you can set the env var `TMUX_SLAY_SESSION`:

```bash
TMUX_SLAY_SESSION="MY_SESSION_NAME"
```

## 🌅 Init window

`tmux-slay` keeps its session alive by creating an empty init-window named
`bg-init`.

To change it you need to set `TMUX_SLAY_INIT_WINDOW_TITLE`:

```bash
TMUX_SLAY_INIT_WINDOW_TITLE="MY_INIT_WINDOW_TITLE"
```

## 🐛 Debug mode

To debug `tmux-slay` just set `TMUX_SLAY_DEBUG` to any value:

```bash
TMUX_SLAY_DEBUG=1
```

To debug commands started with `tmux-slay` the best thing to do is to enable the
`remain-on-exit` options for the session, so that you don't loose the logs of
your command:

```bash
tmux set-hook -t ${TMUX_SLAY_SESSION:-bg} window-linked 'set remain-on-exit on'
```

# 🧪 Examples

## 💻 Run an auto-reconnecting reverse SSH tunnel to the current machine

```bash
tmux-slay run -l -c -u -n ssh-forward -- \
  ssh -o ExitOnForwardFailure=yes -R 22222:localhost:22 user@myvps.example.com
```
