#!/bin/bash
# PostToolUse hook: Run node --check on backend JS files after edits
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ "$file" == *server.js ]] || [[ "$file" == *lib/*.js ]]; then
  result=$(node --check "$file" 2>&1)
  if [ $? -ne 0 ]; then
    echo "SYNTAX ERROR in $(basename "$file"):"
    echo "$result"
  fi
fi
