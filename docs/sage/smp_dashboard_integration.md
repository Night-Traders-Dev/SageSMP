# SageSMP Dashboard Integration
# ==============================
# Add SMP protocol monitoring to SageCluster

# Add to main.py after prometheus_metrics endpoint:

# ============================================================================
# SMP Status Endpoint
# ============================================================================

@app.get("/api/smp-status")
async def smp_status():
    """Get SageSMP protocol status for cluster nodes"""
    def check_smp_process(pattern):
        try:
            result = subprocess.run(
                ["pgrep", "-f", pattern],
                capture_output=True, text=True, timeout=2
            )
            return result.returncode == 0
        except Exception:
            return False
    
    def check_remote_smp(host, user):
        try:
            cmd = f"ssh -oConnectTimeout=2 {user}@{host} 'pgrep -f rpi' 2>/dev/null || true"
            result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=3)
            return bool(result.stdout.strip())
        except Exception:
            return False
    
    smp = {
        "orangepi_relay": {
            "enabled": True,
            "running": check_smp_process("orangepi_relay"),
            "port": 42000,
            "secret": "orangepi_cluster_secret_2026"
        },
        "rpi2_client": {
            "enabled": True,
            "running": check_remote_smp("10.42.1.109", "evelyn"),
            "host": "10.42.1.109",
            "port": 42001
        },
        "rpi4_client": {
            "enabled": True,
            "running": check_remote_smp("10.42.0.141", "ubuntu"),
            "host": "10.42.0.141",
            "port": 42002
        }
    }
    
    return JSONResponse({"smp": smp, "timestamp": time.time()})