#!/bin/bash
# PreToolUse hook: Block direct editing of package-lock.json
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ "$(basename "$file")" == "package-lock.json" ]]; then
  echo "BLOCKED: Do not edit package-lock.json directly. Use npm install/uninstall instead."
  exit 2
fi
