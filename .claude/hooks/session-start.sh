#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo "Session start hook: environment ready (no dependencies to install)."

# Telegram notification
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-8737647223:AAGnA7eSOVtFtaA3uF-LYdb58k733XUlSNA}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-8603234239}"

curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="Claude Code session started in: ${CLAUDE_PROJECT_DIR:-unknown}" \
  > /dev/null || echo "Telegram notification failed (non-fatal)"
