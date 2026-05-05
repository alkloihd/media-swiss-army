#!/bin/bash
# PostToolUse hook: Notify when backend files change and server restart is needed
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ "$file" == *server.js ]] || [[ "$file" == *lib/*.js ]]; then
  echo "Note: Backend file changed ($(basename "$file")). Server restart needed for changes to take effect."
fi
