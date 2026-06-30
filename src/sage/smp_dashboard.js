# SMP JS Integration
# ==================
# JavaScript for SageSMP protocol monitoring in dashboard

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
        
        // Create SMP container if not exists
        let smpContainer = document.getElementById('smp-container');
        if (!smpContainer) {
            const main = document.querySelector('main');
            if (main && smp) {
                smpContainer = document.createElement('div');
                smpContainer.id = 'smp-section';
                smpContainer.innerHTML = `
                    <div>
                        <h2 class="text-sm uppercase tracking-wider text-slate-400 font-semibold mb-4">SageSMP Protocol</h2>
                        <div class="grid grid-cols-1 sm:grid-cols-3 gap-6" id="smp-container"></div>
                    </div>
                `;
                main.insertBefore(smpContainer, main.firstChild);
            }
        }
        
        if (smpContainer) {
            const container = document.getElementById('smp-container');
            if (container) {
                let html = '';
                for (const [name, info] of Object.entries(smp)) {
                    html += createSMPCardHTML(name, info);
                }
                container.innerHTML = html;
            }
        }
    } catch (e) {
        console.warn('Failed to fetch SMP status:', e);
    }
}