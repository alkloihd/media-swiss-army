#!/bin/bash
# PostToolUse hook: Auto-format with Prettier after file edits
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

if [[ "$file" =~ \.(js|css|html|json)$ ]] && [[ -f "$file" ]]; then
  cd "$repo_root" && npx prettier --write "$file" 2>/dev/null
fi
