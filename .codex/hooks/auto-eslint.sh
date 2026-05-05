#!/bin/bash
# PostToolUse hook: Auto-lint JS files with ESLint after edits
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"

if [[ "$file" == *.js ]] && [[ -f "$file" ]]; then
  cd "$repo_root"
  result=$(npx eslint "$file" 2>&1)
  if [ $? -ne 0 ]; then
    echo "ESLint issues in $(basename "$file"):"
    echo "$result"
  fi
fi
