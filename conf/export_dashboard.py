#!/usr/bin/env python3
"""Write current dashboard JSON to provisioning format."""
import requests, json, sys

URL = "http://192.168.254.44:8081/api/proxy/grafana"
r = requests.get(f"{URL}/api/dashboards/uid/a2lcqz", timeout=10, auth=("admin", "admin"))
d = r.json()

# Strip meta, keep only the dashboard model
dash = d["dashboard"]
# Remove fields that are set by Grafana
for field in ("id", "version", "uid"):
    dash.pop(field, None)

# Write as provisioning JSON
with open("/home/kraken/Devel/SageSMP/conf/grafana/provisioning/dashboards/sagesmp_cluster.json", "w") as f:
    json.dump(dash, f, indent=2)

print("Done")
print(f"Title: {dash.get('title')}")
print(f"Panels: {len(dash.get('panels', []))}")
