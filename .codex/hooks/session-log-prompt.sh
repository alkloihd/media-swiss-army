#!/bin/bash
# UserPromptSubmit hook: Log user prompts to session activity log
# Matcher: (empty - matches all)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
dir="$repo_root/.agents/work-sessions/$(TZ=Africa/Johannesburg date '+%Y-%m-%d')"
mkdir -p "$dir"
echo "[$(TZ=Africa/Johannesburg date '+%Y-%m-%d %H:%M SAST')] User prompt received" >> "$dir/session-activity.log" 2>/dev/null
