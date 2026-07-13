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

# Logging status
PIHOLE_LOG=$(pihole logging 2>&1)
if echo "$PIHOLE_LOG" | grep -qi "enabled"; then
  LOGGING="enabled"
else
  LOGGING="disabled"
fi

# Privacy level from FTL config
PRIVACY=$(grep -i "^PRIVACYLEVEL" /etc/pihole/pihole-FTL.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
[ -z "$PRIVACY" ] && PRIVACY=0

# Query count today from Pi-hole API
QUERIES=$(pihole -c -j 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('queries_today',0))" 2>/dev/null || echo 0)

# Packet capture status
PCAP_ACTIVE=$(systemctl is-active pihole-capture 2>/dev/null || echo "inactive")

# Strip newlines and default empty values
LISTENING=$(echo "$LISTENING" | tr -d '\n' | tr -d '\r')
FTL_PID=$(echo "$FTL_PID" | tr -d '\n' | tr -d '\r')
QUERIES=$(echo "$QUERIES" | tr -d '\n' | tr -d '\r')
[ -z "$LISTENING" ] && LISTENING=0
[ -z "$FTL_PID" ] && FTL_PID=0
[ -z "$QUERIES" ] && QUERIES=0
[ -z "$PIHOLE_ACTIVE" ] && PIHOLE_ACTIVE=unknown
[ -z "$BLOCKING" ] && BLOCKING=disabled
[ -z "$LOGGING" ] && LOGGING=disabled
[ -z "$PCAP_ACTIVE" ] && PCAP_ACTIVE=inactive

printf '{"pihole_active":"%s","blocking":"%s","logging":"%s","privacy_level":%s,"queries_today":%s,"listening":%s,"ftl_pid":%s,"pcap_active":"%s"}\n' \
  "$PIHOLE_ACTIVE" "$BLOCKING" "$LOGGING" "$PRIVACY" "$QUERIES" "$LISTENING" "$FTL_PID" "$PCAP_ACTIVE" \
  > /tmp/sagesmp_pihole.json
