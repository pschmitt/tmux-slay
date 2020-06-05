# tmux-slay

## Dependencies

bash and tmux 🤷‍♂️

## Installation

### Using zinit

```zsh
zinit light-mode wait lucid as"command" \
  mv"tmux-slay.sh -> tmux-slay" sbin"tmux-slay" \
  atload"alias tslay=tmux-slay" \
  for @pschmitt/tmux-slay
```

### Otherwise

Just get `tmux-slay.sh` and put it in your PATH.

## Usage

```zsh
# Run single command
tmux-slay run COMMAND

# List running commands
tmux-slay list

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
