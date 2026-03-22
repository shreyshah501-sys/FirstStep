#!/bin/bash
# Telegram Remote Control Daemon for Claude Code
# Polls for messages, executes them as Claude prompts or shell commands,
# and sends results back. Only accepts messages from the authorized chat ID.

BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-8737647223:AAGnA7eSOVtFtaA3uF-LYdb58k733XUlSNA}"
AUTHORIZED_CHAT_ID="${TELEGRAM_CHAT_ID:-8603234239}"
API="https://api.telegram.org/bot${BOT_TOKEN}"
OFFSET_FILE="/tmp/telegram_control_offset"
LOG_FILE="/tmp/telegram_control.log"
MAX_RESPONSE_LENGTH=4000  # Telegram message limit is 4096 chars

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

send_message() {
  local chat_id="$1"
  local text="$2"
  # Truncate if too long
  if [ ${#text} -gt $MAX_RESPONSE_LENGTH ]; then
    text="${text:0:$MAX_RESPONSE_LENGTH}
...[truncated]"
  fi
  curl -s -X POST "${API}/sendMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "text=${text}" \
    > /dev/null
}

handle_message() {
  local chat_id="$1"
  local text="$2"

  log "Received from ${chat_id}: ${text}"

  # Security: only process authorized chat
  if [ "$chat_id" != "$AUTHORIZED_CHAT_ID" ]; then
    log "Ignored message from unauthorized chat: ${chat_id}"
    return
  fi

  # /shell <cmd> → execute shell command
  if [[ "$text" == /shell* ]]; then
    local cmd="${text#/shell }"
    log "Executing shell: ${cmd}"
    send_message "$chat_id" "Running: \`${cmd}\`"
    local output
    output=$(bash -c "$cmd" 2>&1) || true
    send_message "$chat_id" "${output:-<no output>}"

  # /status → show session info
  elif [ "$text" = "/status" ]; then
    local info
    info="Project: ${CLAUDE_PROJECT_DIR:-unknown}
Uptime: $(uptime -p 2>/dev/null || uptime)
PWD: $(pwd)"
    send_message "$chat_id" "$info"

  # /help → list commands
  elif [ "$text" = "/help" ]; then
    send_message "$chat_id" "Commands:
/shell <cmd> — run a shell command
/status — show session info
/help — show this help
<anything else> — ask Claude"

  # Everything else → Claude prompt
  else
    log "Prompting Claude: ${text}"
    send_message "$chat_id" "Thinking..."
    local response
    response=$(claude -p "$text" --output-format text 2>&1) || \
      response="Error: Claude prompt failed."
    send_message "$chat_id" "$response"
  fi
}

main() {
  log "Telegram control daemon started (authorized chat: ${AUTHORIZED_CHAT_ID})"

  # Load offset
  local offset=0
  if [ -f "$OFFSET_FILE" ]; then
    offset=$(cat "$OFFSET_FILE")
  fi

  while true; do
    # Long-poll for updates (30s timeout)
    local updates
    updates=$(curl -s --max-time 35 \
      "${API}/getUpdates?offset=${offset}&timeout=30" 2>/dev/null) || {
      sleep 5
      continue
    }

    # Parse each update
    local count
    count=$(echo "$updates" | python3 -c "
import sys, json
data = json.load(sys.stdin)
results = data.get('result', [])
print(len(results))
for r in results:
    uid = r.get('update_id', 0)
    msg = r.get('message', {})
    chat_id = str(msg.get('chat', {}).get('id', ''))
    text = msg.get('text', '')
    if chat_id and text:
        print(f'{uid}\t{chat_id}\t{text}')
" 2>/dev/null) || { sleep 5; continue; }

    local line_num=0
    while IFS= read -r line; do
      if [ $line_num -eq 0 ]; then
        line_num=1
        continue  # skip count line
      fi
      local update_id chat_id text
      update_id=$(echo "$line" | cut -f1)
      chat_id=$(echo "$line" | cut -f2)
      text=$(echo "$line" | cut -f3-)

      handle_message "$chat_id" "$text"
      offset=$((update_id + 1))
      echo "$offset" > "$OFFSET_FILE"
    done <<< "$count"

    # Small pause to avoid hammering API on errors
    sleep 1
  done
}

main
