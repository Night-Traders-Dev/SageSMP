#!/bin/bash
# SageSMP: Scheduled cross-compile for Pi4
# Runs sagemake --all and captures output for heartbeat telemetry
# Called by cron daily at 3:00 AM

LOG_FILE="/tmp/sagesmp_compile_result.json"
# Resolve repo dir regardless of invoking user (cron vs sudo)
if [ -d /home/ubuntu/SageSMP ]; then
  WORK_DIR="/home/ubuntu/SageSMP"
elif [ -d "$HOME/SageSMP" ]; then
  WORK_DIR="$HOME/SageSMP"
else
  WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)/SageSMP"
fi

cd "$WORK_DIR" || { printf '{"error":"cd failed","ts":"%s"}\n' "$(date -Iseconds)" > "$LOG_FILE"; exit 1; }

START_TS=$(date -Iseconds)
OUTPUT=$(./sagemake --all 2>&1)
EXIT_CODE=$?
END_TS=$(date -Iseconds)
DURATION=$(( $(date +%s) - $(date -d "$START_TS" +%s) ))
STATUS="ok"
[ $EXIT_CODE -ne 0 ] && STATUS="fail"

# Build a JSON-safe output string (escape quotes, backslashes; \n for newlines)
# Use python3 for correct JSON string escaping, then strip outer quotes for embedding.
SAFE_OUTPUT=$(echo "$OUTPUT" | head -200 | python3 -c 'import sys,json; sys.stdout.write(json.dumps(sys.stdin.read())[1:-1])')

printf '{"status":"%s","exit_code":%d,"start":"%s","end":"%s","duration":%d,"output":"%s"}\n' \
  "$STATUS" "$EXIT_CODE" "$START_TS" "$END_TS" "$DURATION" \
  "$SAFE_OUTPUT" \
  > "$LOG_FILE"
