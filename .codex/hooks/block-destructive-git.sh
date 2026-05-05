#!/bin/bash
# PreToolUse hook: Block destructive git commands
# Matcher: Bash

input=$(cat)
cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

if echo "$cmd" | grep -qE '(push.*--force|push.*-f |reset.*--hard|clean.*-f|branch.*-D)'; then
  echo "BLOCKED: Destructive git command detected. Please confirm with the user first."
  exit 2
fi
