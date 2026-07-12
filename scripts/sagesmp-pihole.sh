#!/bin/bash
# SageSMP: Capture Pi-hole status for heartbeat telemetry
# Called by cron every 5 minutes on Pi2

PIHOLE_ACTIVE=$(systemctl is-active pihole-FTL 2>/dev/null || echo "unknown")
PIHOLE_STAT=$(pihole status 2>&1)

if echo "$PIHOLE_STAT" | grep -q "enabled"; then
  BLOCKING="enabled"
else
  BLOCKING="disabled"
fi

LISTENING=$(echo "$PIHOLE_STAT" | grep -c "listening on port" || true)
FTL_PID=$(systemctl show pihole-FTL --property=MainPID 2>/dev/null | cut -d= -f2 || true)

# Strip newlines and default empty values
LISTENING=$(echo "$LISTENING" | tr -d '\n' | tr -d '\r')
FTL_PID=$(echo "$FTL_PID" | tr -d '\n' | tr -d '\r')
[ -z "$LISTENING" ] && LISTENING=0
[ -z "$FTL_PID" ] && FTL_PID=0
[ -z "$PIHOLE_ACTIVE" ] && PIHOLE_ACTIVE=unknown
[ -z "$BLOCKING" ] && BLOCKING=disabled

printf '{"pihole_active":"%s","blocking":"%s","listening":%s,"ftl_pid":%s}\n' \
  "$PIHOLE_ACTIVE" "$BLOCKING" "$LISTENING" "$FTL_PID" \
  > /tmp/sagesmp_pihole.json
