#!/bin/bash
# SageSMP Dashboard Integration Script
# Run this on OrangePi to add SMP monitoring

set -e

CLUSTER_DIR="$HOME/SageCluster"
SMP_DIR="$HOME/SageSMP"
BIN_DIR="$SMP_DIR/bin"

echo "=== SageSMP Dashboard Integration ==="

# Ensure SMP directory exists
if [ ! -d "$SMP_DIR" ]; then
    echo "Cloning SageSMP..."
    git clone https://github.com/Night-Traders-Dev/SageSMP.git "$SMP_DIR"
fi

# Build binaries if needed
if [ ! -f "$BIN_DIR/orangepi_relay" ]; then
    echo "Building OrangePi relay..."
    cd "$SMP_DIR"
    ./sagemake --orangepi 2>/dev/null || echo "Build may require Sage compiler"
fi

# Add SMP status endpoint to main.py
echo "Adding SMP status endpoint..."

# Create a patch file for SMP endpoint
cat >> "$CLUSTER_DIR/smp_endpoints.py" << 'EOF'
# SageSMP Endpoints - Add to main.py

import subprocess
import time

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
EOF

# Add SMP JS to static
mkdir -p "$CLUSTER_DIR/static/js"
cat > "$CLUSTER_DIR/static/js/smp_monitor.js" << 'EOF'
// SageSMP Protocol Monitor

const SMP_ICONS = {
    orangepi_relay: '<i class="fa-brands fa-linux text-xl text-yellow-500"></i>',
    rpi2_client: '<i class="fa-brands fa-raspberry-pi text-xl" style="color:#C51A4A"></i>',
    rpi4_client: '<i class="fa-brands fa-ubuntu text-xl" style="color:#E95420"></i>'
};

function createSMPCardHTML(name, data) {
    const running = data.running;
    const sc = running ? 'bg-emerald-500' : 'bg-red-500';
    const st = running ? 'Running' : 'Stopped';
    const icon = SMP_ICONS[name] || '<i class="fa-solid fa-hashtag text-xl text-slate-400"></i>';
    
    return `
        <div class="bg-slate-800 rounded-xl p-5 border border-slate-700/50 shadow-lg">
            <div class="flex items-center justify-between mb-3">
                <div class="flex items-center space-x-3">
                    <div class="w-10 h-10 rounded-full bg-slate-700 flex items-center justify-center border border-slate-600">${icon}</div>
                    <div><h3 class="text-lg font-semibold text-white">${name.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}</h3></div>
                </div>
                <span class="px-2 py-1 text-xs rounded-full ${sc} text-white">${st}</span>
            </div>
            <div class="grid grid-cols-2 gap-4 text-sm">
                <div><p class="text-xs text-slate-500 uppercase tracking-wider mb-1">Port</p><p class="text-slate-300 font-mono">${data.port || 'N/A'}</p></div>
                <div><p class="text-xs text-slate-500 uppercase tracking-wider mb-1">Host</p><p class="text-slate-300 font-mono">${data.host || 'localhost'}</p></div>
            </div>
        </div>
    `;
}

async function updateSMPStatus() {
    try {
        const resp = await fetch('/api/smp-status');
        const data = await resp.json();
        const smp = data.smp;
        
        let smpContainer = document.getElementById('smp-container');
        if (!smpContainer) {
            const nodesSection = document.querySelector('h2.text-slate-400.font-semibold');
            if (nodesSection) {
                const parent = nodesSection.closest('div');
                const smpSection = document.createElement('div');
                smpSection.innerHTML = `
                    <h2 class="text-sm uppercase tracking-wider text-slate-400 font-semibold mb-4">SageSMP Protocol</h2>
                    <div class="grid grid-cols-1 sm:grid-cols-3 gap-6" id="smp-container"></div>
                `;
                nodesSection.parentNode.insertBefore(smpSection, parent);
            }
        }
        
        const container = document.getElementById('smp-container');
        if (container && smp) {
            let html = '';
            for (const [name, info] of Object.entries(smp)) {
                html += createSMPCardHTML(name, info);
            }
            container.innerHTML = html;
        }
    } catch (e) {
        console.warn('SMP status error:', e);
    }
}
EOF

# Instructions to add SMP endpoint to main.py
echo ""
echo "=== Manual Integration Required ==="
echo ""
echo "Add the following to main.py after the prometheus-metrics endpoint:"
echo ""
cat "$CLUSTER_DIR/smp_endpoints.py"
echo ""
echo "Then add 'src=\"/static/js/smp_monitor.js\"' to index.html before </body>"
echo ""
echo "Done!"