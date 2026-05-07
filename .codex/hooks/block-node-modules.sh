#!/bin/bash
# PreToolUse hook: Block editing files inside node_modules/
# Matcher: Edit|Write

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ "$file" == *node_modules* ]]; then
  echo "BLOCKED: Do not edit files in node_modules/. Install packages via npm instead."
  exit 2
fi
