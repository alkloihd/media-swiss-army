#!/bin/bash
# Stop hook: Log session end to session activity log
# Matcher: (empty - matches all)

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
dir="$repo_root/.agents/work-sessions/$(TZ=Africa/Johannesburg date '+%Y-%m-%d')"
mkdir -p "$dir"
echo "[$(TZ=Africa/Johannesburg date '+%Y-%m-%d %H:%M SAST')] Agent session ended" >> "$dir/session-activity.log"
