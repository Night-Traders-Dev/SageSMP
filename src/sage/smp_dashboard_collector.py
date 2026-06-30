# SMP Status Collector
# ====================
# Standalone script for collecting SageSMP client status

import subprocess
import json

def check_smp_relay():
    """Check if OrangePi SMP relay is running"""
    try:
        result = subprocess.run(
            ["pgrep", "-f", "orangepi_relay"],
            capture_output=True, text=True, timeout=2
        )
        return result.returncode == 0
    except Exception:
        return False

def check_smp_client(host, user=None):
    """Check if SMP client is running on a remote node"""
    if user:
        cmd = f"ssh -oConnectTimeout=2 {user}@{host} 'pgrep -f rpi' 2>/dev/null || true"
    else:
        cmd = f"ssh -oConnectTimeout=2 {host} 'pgrep -f rpi' 2>/dev/null || true"
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=3)
        return bool(result.stdout.strip())
    except Exception:
        return False

def main():
    status = {
        "orangepi": {
            "running": check_smp_relay(),
            "port": 42000,
            "clients_connected": 0
        },
        "rpi2": {
            "running": check_smp_client("10.42.1.109", "evelyn"),
            "host": "10.42.1.109",
            "port": 42001
        },
        "rpi4": {
            "running": check_smp_client("10.42.0.141", "ubuntu"),
            "host": "10.42.0.141",
            "port": 42002
        }
    }
    
    # Count connected clients
    if status["rpi2"]["running"]:
        status["orangepi"]["clients_connected"] += 1
    if status["rpi4"]["running"]:
        status["orangepi"]["clients_connected"] += 1
    
    print(json.dumps(status, indent=2))

if __name__ == "__main__":
    main()