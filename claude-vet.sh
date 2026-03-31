#!/usr/bin/env zsh
# claude-vet — review remote scripts with Claude before executing them
# https://github.com/dalsh/claude-vet

claude-vet() {
  local full_cmd="$*"
  local _cv="[claude-vet]"

  if [[ -z "$full_cmd" ]]; then
    echo "$_cv usage: claude-vet 'curl -sSfL https://... | sh -s -- [args]'" >&2
    return 1
  fi

  # Resolve prompt file relative to this script
  local script_dir="${CLAUDE_VET_DIR:-${0:A:h}}"
  local prompt_file="${script_dir}/prompts/review.txt"

  if [[ ! -f "$prompt_file" ]]; then
    echo "$_cv prompt file not found at ${prompt_file}" >&2
    return 1
  fi

  # Extract all https URLs from the command
  local urls
  urls=$(echo "$full_cmd" | grep -oE 'https?://[^ |><"]+')

  if [[ -z "$urls" ]]; then
    echo "$_cv no URL found in command — refusing to eval blindly" >&2
    return 1
  fi

  # Fetch each URL
  local all_scripts=""
  while IFS= read -r url; do
    echo "$_cv fetching: $url" >&2
    local content
    content=$(curl -sSfL "$url" 2>&1) || {
      echo "$_cv failed to fetch $url" >&2
      return 1
    }
    all_scripts+="=== ${url} ===\n${content}\n\n"
  done <<< "$urls"

  # Build prompt from template
  local prompt
  prompt="$(cat "$prompt_file")"
  prompt="${prompt//\{\{COMMAND\}\}/$full_cmd}"
  prompt="${prompt//\{\{SCRIPTS\}\}/$(printf '%b' "$all_scripts")}"

  # Ask Claude
  echo "$_cv asking Claude to review..." >&2
  local review
  review=$(claude -p "$prompt" 2>/dev/null)

  if [[ -z "$review" ]]; then
    echo "$_cv no response from Claude — aborting" >&2
    return 1
  fi

  local verdict
  verdict=$(printf '%s' "$review" | grep -oE '^VERDICT: (SAFE|CAUTION|UNSAFE)' | awk '{print $2}')

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━ Claude Review ━━━━━━━━━━━━━━━━━━━━"
  printf '%s\n' "$review"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$verdict" in
    SAFE)
      echo "$_cv SAFE — executing." >&2
      eval "$full_cmd"
      ;;
    CAUTION)
      echo "$_cv CAUTION — proceed anyway? [y/N]" >&2
      read -r response </dev/tty
      if [[ "$response" =~ ^[Yy]$ ]]; then
        eval "$full_cmd"
      else
        echo "$_cv aborted." >&2
        return 1
      fi
      ;;
    UNSAFE|"")
      echo "$_cv UNSAFE — aborting." >&2
      return 2
      ;;
  esac
}
