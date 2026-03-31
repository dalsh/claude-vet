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

  if ! command -v jq &>/dev/null; then
    echo "$_cv jq is required but not found in PATH" >&2
    return 1
  fi

  # Resolve prompt files relative to this script
  local script_dir="${CLAUDE_VET_DIR:-${0:A:h}}"
  local system_prompt_file="${script_dir}/prompts/system.txt"
  local user_prompt_file="${script_dir}/prompts/user.txt"

  if [[ ! -f "$system_prompt_file" ]] || [[ ! -f "$user_prompt_file" ]]; then
    echo "$_cv prompt files not found in ${script_dir}/prompts/" >&2
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

  # Build user message from template (untrusted content goes here)
  local user_msg
  user_msg="$(cat "$user_prompt_file")"
  user_msg="${user_msg//\{\{COMMAND\}\}/$full_cmd}"
  user_msg="${user_msg//\{\{SCRIPTS\}\}/$(printf '%b' "$all_scripts")}"

  # JSON schema for structured output validation
  local json_schema='{"type":"object","properties":{"verdict":{"type":"string","enum":["SAFE","CAUTION","UNSAFE"]},"reason":{"type":"string"},"findings":{"type":"array","items":{"type":"string"}}},"required":["verdict","reason","findings"],"additionalProperties":false}'

  # Ask Claude — system prompt (trusted) is separate from user message (untrusted)
  echo "$_cv asking Claude to review..." >&2
  local review
  review=$(printf '%s' "$user_msg" | claude -p \
    --system-prompt-file "$system_prompt_file" \
    --json-schema "$json_schema" \
    --output-format json \
    2>/dev/null)

  if [[ -z "$review" ]]; then
    echo "$_cv no response from Claude — aborting" >&2
    return 1
  fi

  # Parse structured_output from CLI JSON envelope using jq
  local verdict reason findings
  verdict=$(printf '%s' "$review" | jq -r '.structured_output.verdict // empty' 2>/dev/null)
  reason=$(printf '%s' "$review" | jq -r '.structured_output.reason // empty' 2>/dev/null)
  findings=$(printf '%s' "$review" | jq -r '.structured_output.findings[]? | "- " + .' 2>/dev/null)

  # Default-deny: treat unparseable responses as UNSAFE
  if [[ -z "$verdict" ]]; then
    echo "$_cv could not determine verdict — treating as UNSAFE" >&2
    verdict="UNSAFE"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━ Claude Review ━━━━━━━━━━━━━━━━━━━━"
  echo "VERDICT: $verdict"
  echo "REASON: $reason"
  if [[ -n "$findings" ]]; then
    echo "DETAILS:"
    printf '%s\n' "$findings"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  case "$verdict" in
    SAFE)
      if [[ "$CLAUDE_VET_AUTO_EXECUTE" == "1" ]]; then
        echo "$_cv SAFE — auto-executing (CLAUDE_VET_AUTO_EXECUTE=1)." >&2
        eval "$full_cmd"
        return $?
      else
        echo "$_cv SAFE — execute? [Y/n]" >&2
        read -r response </dev/tty
        if [[ "$response" =~ ^[Nn]$ ]]; then
          echo "$_cv aborted." >&2
          return 1
        fi
        eval "$full_cmd"
        return $?
      fi
      ;;
    CAUTION)
      echo "$_cv CAUTION — proceed anyway? [y/N]" >&2
      read -r response </dev/tty
      if [[ "$response" =~ ^[Yy]$ ]]; then
        eval "$full_cmd"
        return $?
      else
        echo "$_cv aborted." >&2
        return 1
      fi
      ;;
    UNSAFE|*)
      echo "$_cv UNSAFE — aborting." >&2
      return 2
      ;;
  esac
}
