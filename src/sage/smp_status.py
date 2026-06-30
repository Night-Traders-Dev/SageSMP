# SageSMP Dashboard Integration
# ==============================
# Add SMP protocol monitoring to SageCluster dashboard

import subprocess
import time
import os

SMP_DIR = "/home/orangepi/SageSMP"
SMP_RELAY_BINARY = os.path.join(SMP_DIR, "bin", "orangepi_relay")
SMP_RPI2_CLIENT = "rpi2_client"
SMP_RPI4_CLIENT = "rpi4_client"

def check_process_running(process_pattern):
    """Check if a process matching pattern is running"""
    try:
        result = subprocess.run(
            ["pgrep", "-f", process_pattern],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            pids = result.stdout.strip().split('\n')
            return pids[0] if pids else None
    except Exception:
        pass
    return None

def get_smp_status():
    """Collect SageSMP protocol status for all nodes"""
    smp_status = {
        "orangepi": {
            "enabled": True,
            "running": False,
            "pid": None,
            "port": 42000,
            "clients": [],
            "messages_sent": 0,
            "messages_received": 0
        },
        "rpi2": {
            "enabled": True,
            "running": False,
            "pid": None,
            "host": "10.42.1.109",
            "port": 42001,
            "last_temp": "N/A",
            "last_load": "N/A"
        },
        "rpi4": {
            "enabled": True,
            "running": False,
            "pid": None,
            "host": "10.42.0.141",
            "port": 42002,
            "last_temp": "N/A",
            "last_load": "N/A"
        }
    }
    
    # Check OrangePi relay
    pid = check_process_running("orangepi_relay")
    smp_status["orangepi"]["running"] = pid is not None
    smp_status["orangepi"]["pid"] = pid
    
    # Check RPi2 client
    pid = check_process_running(SMP_RPI2_CLIENT)
    smp_status["rpi2"]["running"] = pid is not None
    smp_status["rpi2"]["pid"] = pid
    if not pid:
        try:
            out = subprocess.run(
                ["ssh", "-oConnectTimeout=2", "evelyn@10.42.1.109", f"pgrep -f {SMP_RPI2_CLIENT}"],
                capture_output=True, text=True, timeout=3
            )
            if out.returncode == 0:
                pids = out.stdout.strip().split('\n')
                smp_status["rpi2"]["running"] = True
                smp_status["rpi2"]["pid"] = pids[0] if pids else None
        except Exception:
            pass
    
    # Check RPi4 client
    pid = check_process_running(SMP_RPI4_CLIENT)
    smp_status["rpi4"]["running"] = pid is not None
    smp_status["rpi4"]["pid"] = pid
    if not pid:
        try:
            out = subprocess.run(
                ["ssh", "-oConnectTimeout=2", "ubuntu@10.42.0.141", f"pgrep -f {SMP_RPI4_CLIENT}"],
                capture_output=True, text=True, timeout=3
            )
            if out.returncode == 0:
                pids = out.stdout.strip().split('\n')
                smp_status["rpi4"]["running"] = True
                smp_status["rpi4"]["pid"] = pids[0] if pids else None
        except Exception:
            pass
    
    return smp_status

if __name__ == "__main__":
    import json
    print(json.dumps(get_smp_status(), indent=2))