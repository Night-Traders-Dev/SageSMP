#!/bin/bash
# SageSMP: Capture Grafana + Prometheus status for heartbeat telemetry
# Called by cron every 5 minutes on Pi4

GRAFANA_ACTIVE=$(systemctl is-active grafana-server 2>/dev/null || echo "unknown")
GRAFANA_API=$(curl -sf http://localhost:3000/api/health 2>/dev/null)
GRAFANA_VERSION=$(echo "$GRAFANA_API" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || true)
PROM_ACTIVE=$(systemctl is-active prometheus-node-exporter 2>/dev/null || echo "unknown")
PROM_MAIN=$(systemctl is-active prometheus 2>/dev/null || echo "unknown")
UPTIME=$(systemctl show grafana-server --property=ActiveEnterTimestamp 2>/dev/null | cut -d= -f2 || true)

# Strip newlines and default empty values
GRAFANA_VERSION=$(echo "$GRAFANA_VERSION" | tr -d '\n' | tr -d '\r')
UPTIME=$(echo "$UPTIME" | tr -d '\n' | tr -d '\r')
[ -z "$GRAFANA_VERSION" ] && GRAFANA_VERSION="n/a"
[ -z "$GRAFANA_ACTIVE" ] && GRAFANA_ACTIVE=unknown
[ -z "$PROM_ACTIVE" ] && PROM_ACTIVE=unknown
[ -z "$PROM_MAIN" ] && PROM_MAIN=unknown
[ -z "$UPTIME" ] && UPTIME=unknown

printf '{"grafana":"%s","grafana_version":"%s","prometheus":"%s","prometheus_main":"%s","uptime":"%s"}\n' \
  "$GRAFANA_ACTIVE" "$GRAFANA_VERSION" "$PROM_ACTIVE" "$PROM_MAIN" "$UPTIME" \
  > /tmp/sagesmp_services.json
