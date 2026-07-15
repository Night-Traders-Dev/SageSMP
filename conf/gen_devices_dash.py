#!/usr/bin/env python3
"""Generate per-device detail dashboard JSON for Grafana provisioning."""
import json, sys

UID = "bfq8ajo0pyjggb"  # Prometheus datasource UID
DEVICES = ["orangepi", "pi2", "pi4"]

panels = []
y = 0

for dev in DEVICES:
    panels.append({
        "title": f"{dev.title()} — CPU Temp",
        "type": "gauge",
        "datasource": {"type": "prometheus", "uid": UID},
        "fieldConfig": {"defaults": {"min": 0, "max": 100, "unit": "celsius", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": None}, {"color": "orange", "value": 70}, {"color": "red", "value": 85}]}}},
        "gridPos": {"h": 6, "w": 4, "x": 0, "y": y},
        "targets": [{"expr": f'sagesmp_cpu_temp_celsius{{device="{dev}"}}', "legendFormat": dev, "refId": "A"}]
    })
    panels.append({
        "title": f"{dev.title()} — CPU Load",
        "type": "stat",
        "datasource": {"type": "prometheus", "uid": UID},
        "gridPos": {"h": 6, "w": 4, "x": 4, "y": y},
        "targets": [{"expr": f'sagesmp_cpu_load{{device="{dev}"}}', "legendFormat": dev, "refId": "A"}]
    })
    panels.append({
        "title": f"{dev.title()} — Memory",
        "type": "stat",
        "datasource": {"type": "prometheus", "uid": UID},
        "fieldConfig": {"defaults": {"unit": "bytes"}},
        "gridPos": {"h": 6, "w": 4, "x": 8, "y": y},
        "targets": [{"expr": f'sagesmp_memory_available_bytes{{device="{dev}"}}', "legendFormat": "Available", "refId": "A"},
                    {"expr": f'sagesmp_memory_total_bytes{{device="{dev}"}}', "legendFormat": "Total", "refId": "B"}]
    })
    panels.append({
        "title": f"{dev.title()} — CPU Freq",
        "type": "stat",
        "datasource": {"type": "prometheus", "uid": UID},
        "fieldConfig": {"defaults": {"unit": "hz"}},
        "gridPos": {"h": 6, "w": 4, "x": 12, "y": y},
        "targets": [{"expr": f'sagesmp_cpu_freq_hz{{device="{dev}"}}', "legendFormat": dev, "refId": "A"}]
    })
    if dev == "pi4":
        panels.append({
            "title": "GPU Temp",
            "type": "gauge",
            "datasource": {"type": "prometheus", "uid": UID},
            "fieldConfig": {"defaults": {"min": 0, "max": 100, "unit": "celsius"}},
            "gridPos": {"h": 6, "w": 4, "x": 16, "y": y},
            "targets": [{"expr": 'sagesmp_gpu_temp_celsius{device="pi4"}', "legendFormat": "GPU", "refId": "A"}]
        })
        panels.append({
            "title": "Throttling Status",
            "type": "stat",
            "datasource": {"type": "prometheus", "uid": UID},
            "gridPos": {"h": 6, "w": 4, "x": 20, "y": y},
            "targets": [{"expr": 'sagesmp_throttling{device="pi4"}', "legendFormat": "Throttled", "refId": "A"}]
        })
    y += 6

# Uptime + compile panels
panels.append({
    "title": "Relay Uptime",
    "type": "stat",
    "datasource": {"type": "prometheus", "uid": UID},
    "fieldConfig": {"defaults": {"unit": "s"}},
    "gridPos": {"h": 6, "w": 6, "x": 0, "y": y},
    "targets": [{"expr": "sagesmp_relay_uptime_seconds", "legendFormat": "Uptime", "refId": "A"}]
})
panels.append({
    "title": "Compile Count",
    "type": "stat",
    "datasource": {"type": "prometheus", "uid": UID},
    "gridPos": {"h": 6, "w": 6, "x": 6, "y": y},
    "targets": [{"expr": "sagesmp_compile_count", "legendFormat": "Compiles", "refId": "A"}]
})
panels.append({
    "title": "Seconds Since Last Compile",
    "type": "stat",
    "datasource": {"type": "prometheus", "uid": UID},
    "fieldConfig": {"defaults": {"unit": "s"}},
    "gridPos": {"h": 6, "w": 6, "x": 12, "y": y},
    "targets": [{"expr": "sagesmp_seconds_since_last_compile", "legendFormat": "Since last", "refId": "A"}]
})
panels.append({
    "title": "Relay Running",
    "type": "stat",
    "datasource": {"type": "prometheus", "uid": UID},
    "gridPos": {"h": 6, "w": 6, "x": 18, "y": y},
    "targets": [{"expr": "sagesmp_relay_running", "legendFormat": "Relay", "refId": "A"}]
})

dash = {
    "title": "SageSMP Per-Device Detail",
    "tags": ["sagesmp", "devices"],
    "timezone": "browser",
    "refresh": "30s",
    "panels": panels,
    "time": {"from": "now-15m", "to": "now"},
}

with open("/home/kraken/Devel/SageSMP/conf/grafana/provisioning/dashboards/sagesmp_devices.json", "w") as f:
    json.dump(dash, f, indent=2)
print(f"Generated device dashboard: {len(panels)} panels")
