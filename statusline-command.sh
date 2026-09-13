#!/bin/sh
# Claude Code status line — robbyrussell Oh My Zsh theme style
# Format:  ➜  dir git:(branch) ✗
input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
dir=$(basename "$cwd")

# Git segment: blue "git:(" + red branch + blue ")" , yellow ✗ if dirty.
# Omit entirely when cwd is not inside a git repo. Skip optional locks.
git_part=""
if git --no-optional-locks -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(echo "$input" | jq -r '.worktree.branch // empty')
  if [ -z "$branch" ]; then
    branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  fi
  if [ -z "$branch" ]; then
    branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
  dirty=""
  if [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null)" ]; then
    dirty=$(printf " \033[0;33m✗\033[0m")
  fi
  if [ -n "$branch" ]; then
    git_part=$(printf " \033[0;34mgit:(\033[0;31m%s\033[0;34m)\033[0m%s" "$branch" "$dirty")
  fi
fi

# Base: green arrow + cyan directory basename + git segment
out=$(printf "\033[0;32m➜\033[0m  \033[0;36m%s\033[0m%s" "$dir" "$git_part")

printf "%s" "$out"
