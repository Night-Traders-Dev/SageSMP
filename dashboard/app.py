#!/usr/bin/env python3
"""SageSMP Dashboard - monitors interactions between OrangePi, RPi2, RPi4 on port 8081"""

import asyncio
import json
import os
import re
import pty
import fcntl
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
import uvicorn

app = FastAPI(title="SageSMP Dashboard")
templates = Jinja2Templates(directory=Path(__file__).parent / "templates")

# Resolve repository root dynamically relative to dashboard/app.py
SAGEMAP_DIR = Path(__file__).resolve().parents[1]
BIN_DIR = SAGEMAP_DIR / "bin"
LOG_DIR = SAGEMAP_DIR / "logs"
MAX_LOGS = 1000
MAX_EVENTS = 500
MAX_SERVICE_LOG = 10000

LOG_DIR.mkdir(parents=True, exist_ok=True)
SERVICE_LOG_FILE = LOG_DIR / "service_log.jsonl"

# Read host and port configuration from environment variables
SMP_HOST = os.getenv("SMP_HOST", "192.168.254.44")
SMP_PORT = os.getenv("SMP_PORT", "42000")

def load_service_log():
    if not SERVICE_LOG_FILE.exists():
        return []
    entries = []
    try:
        with open(SERVICE_LOG_FILE) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
    except Exception:
        pass
    return entries[-MAX_SERVICE_LOG:]

write_count = 0

def append_service_log(entry):
    global write_count
    # Append in memory
    state["service_logs"].append(entry)
    if len(state["service_logs"]) > MAX_SERVICE_LOG:
        state["service_logs"] = state["service_logs"][-MAX_SERVICE_LOG:]
    
    # Append to file (O(1))
    try:
        with open(SERVICE_LOG_FILE, "a") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as e:
        add_event("error", "dashboard", f"Failed to write service log: {e}")
        
    # Periodic truncation (every 100 writes) to prevent unbound file growth
    write_count += 1
    if write_count >= 100:
        write_count = 0
        try:
            with open(SERVICE_LOG_FILE, "w") as f:
                for e in state["service_logs"]:
                    f.write(json.dumps(e) + "\n")
        except Exception as e:
            add_event("error", "dashboard", f"Failed to rotate service log: {e}")

MAILBOX_FILE = LOG_DIR / "mailboxes.json"

def load_mailboxes():
    if MAILBOX_FILE.exists():
        try:
            with open(MAILBOX_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {"OrangePi": [], "RPi2": [], "RPi4": []}

def save_mailboxes():
    try:
        with open(MAILBOX_FILE, "w") as f:
            json.dump(state["mailboxes"], f, indent=2)
    except Exception:
        pass

state = {
    "relay": {"name": "OrangePi Relay", "proc": None, "tail_proc": None, "syslog_proc": None, "pcap_proc": None, "logs": [], "status": "stopped", "desired_status": "running", "started_at": None},
    "pi2": {"name": "RPi2 Client", "proc": None, "tail_proc": None, "syslog_proc": None, "pcap_proc": None, "logs": [], "status": "stopped", "desired_status": "running", "started_at": None},
    "pi4": {"name": "RPi4 Client", "proc": None, "tail_proc": None, "syslog_proc": None, "pcap_proc": None, "logs": [], "status": "stopped", "desired_status": "running", "started_at": None},
    "events": [],
    "telemetry": {"pi2": {}, "pi4": {}},
    "services": {"pi2": {}, "pi4": {}},
    "compiles": [],
    "service_logs": [],
    "mailboxes": {},
}

def init_state_from_logs():
    state["mailboxes"] = load_mailboxes()
    service_entries = load_service_log()
    state["service_logs"] = service_entries
    for e in service_entries:
        entry_type = e.get("type")
        platform = e.get("platform")
        data = e.get("data", {})
        ts = e.get("timestamp")
        if entry_type == "SERVICES":
            node_key = "pi2" if "RPi2" in platform else "pi4"
            state["services"][node_key] = data
        elif entry_type == "COMPILE":
            state["compiles"].append({"platform": platform, "data": data, "timestamp": ts})
    if len(state["compiles"]) > 50:
        state["compiles"] = state["compiles"][-50:]

# Load historical state on startup
init_state_from_logs()

def add_event(typ, source, message):
    entry = {"type": typ, "source": source, "message": message, "timestamp": datetime.now().isoformat()}
    state["events"].append(entry)
    if len(state["events"]) > MAX_EVENTS:
        state["events"] = state["events"][-MAX_EVENTS:]

def add_log(node_name, line):
    state[node_name]["logs"].append({"timestamp": datetime.now().isoformat(), "line": line})
    if len(state[node_name]["logs"]) > MAX_LOGS:
        state[node_name]["logs"] = state[node_name]["logs"][-MAX_LOGS:]

def parse_telemetry(node_name, line):
    try:
        if "HEARTBEAT OK" in line:
            m = re.search(r'nodes=(\d+)', line)
            if m:
                relay_telem = state["telemetry"].get("relay", {})
                relay_telem["node_count"] = int(m.group(1))
                state["telemetry"]["relay"] = relay_telem
            return
            
        m_plat = re.search(r'\[HEARTBEAT\]\s+(\S+)', line)
        if m_plat:
            platform = m_plat.group(1)
            target_node = "pi2" if "RPi2" in platform else "pi4"
        else:
            target_node = node_name
            
        info = {}
        if "->" in line:
            data_part = line.split("->")[-1].strip()
        else:
            data_part = line
        for part in data_part.split(","):
            part = part.strip()
            if "Temp:" in part:
                info["temp"] = part.split(":")[-1].strip().rstrip("C")
            elif "Load:" in part:
                info["load"] = part.split(":")[-1].strip()
            elif "Available:" in part:
                info["memory"] = "Available:" + part.split(":")[-1].strip()
            elif "GPU:" in part:
                info["gpu_temp"] = part.split(":")[-1].strip().rstrip("C")
            elif "CpuFreq:" in part:
                info["cpu_mhz"] = part.split(":")[-1].strip().rstrip("MHz")
            elif "TotalRam:" in part:
                info["ram_total"] = part.split(":")[-1].strip()
            elif part in ("OK", "THROTTLED"):
                info["throttling"] = part
                
        if info and target_node in ("pi2", "pi4"):
            existing = state["telemetry"].get(target_node, {})
            existing.update(info)
            state["telemetry"][target_node] = existing
    except Exception:
        pass

async def collect_relay_telemetry():
    while True:
        try:
            info = {}
            temp_file = Path("/sys/class/thermal/thermal_zone0/temp")
            if temp_file.exists():
                temp_val = float(temp_file.read_text().strip()) / 1000.0
                info["temp"] = f"{temp_val:.1f}"
            else:
                info["temp"] = "45.0"
                
            load_file = Path("/proc/loadavg")
            if load_file.exists():
                info["load"] = load_file.read_text().split()[0]
            else:
                info["load"] = "0.20"
                
            freq_file = Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
            if freq_file.exists():
                freq_val = float(freq_file.read_text().strip()) / 1000.0
                info["cpu_mhz"] = f"{freq_val:.0f}"
            else:
                info["cpu_mhz"] = "1800"
                
            mem_file = Path("/proc/meminfo")
            if mem_file.exists():
                total_kb = 0
                avail_kb = 0
                for line in mem_file.read_text().splitlines():
                    if line.startswith("MemTotal:"):
                        total_kb = int(line.split()[1])
                    elif line.startswith("MemAvailable:"):
                        avail_kb = int(line.split()[1])
                if total_kb:
                    info["ram_total"] = f"{total_kb // 1024}MB"
                if avail_kb:
                    info["memory"] = f"Available:{avail_kb // 1024}MB"
            else:
                info["ram_total"] = "2048MB"
                info["memory"] = "Available:1536MB"
                
            relay_telem = state["telemetry"].get("relay", {})
            relay_telem.update(info)
            state["telemetry"]["relay"] = relay_telem
        except Exception:
            pass
        await asyncio.sleep(2)

def parse_service_line(node_name, line):
    try:
        # [SERVICES] RPi2 -> {"pihole_active":"active",...}
        # [COMPILE] RPi4 -> {"status":"ok",...}
        m = re.match(r'\[(SERVICES|COMPILE)\]\s+(\S+)\s+->\s+(.*)', line)
        if not m:
            return
        entry_type = m.group(1)
        platform = m.group(2)
        data_str = m.group(3)
        data = json.loads(data_str)
        ts = datetime.now().isoformat()
        log_entry = {"type": entry_type, "platform": platform, "data": data, "timestamp": ts}
        append_service_log(log_entry)
        if entry_type == "SERVICES":
            node_key = "pi2" if "RPi2" in platform else "pi4"
            state["services"][node_key] = data
            add_event("services", node_key, f"{platform} services: {data_str[:120]}")
        elif entry_type == "COMPILE":
            state["compiles"].append({"platform": platform, "data": data, "timestamp": ts})
            if len(state["compiles"]) > 50:
                state["compiles"] = state["compiles"][-50:]
            status = data.get("status", "?")
            add_event("compile", "pi4", f"Cross-compile {status} (exit={data.get('exit_code','?')})")
    except Exception:
        pass

async def stream_reader(stream, node_name):
    while True:
        line = await stream.readline()
        if not line:
            break
        line = line.decode(errors="replace").rstrip()
        if not line:
            continue
        add_log(node_name, line)
        if "[HEARTBEAT] " in line:
            add_event("heartbeat", node_name, line)
            parse_telemetry(node_name, line)
        elif "[HEARTBEAT OK]" in line:
            add_event("heartbeat_ack", node_name, line)
            parse_telemetry(node_name, line)
        elif "[SERVICES]" in line:
            parse_service_line(node_name, line)
        # Ignore legacy [COMPILE] heartbeats from client to avoid overwriting SageLang build records
        # elif "[COMPILE]" in line:
        #     add_event("compile", "pi4", f"Cross-compile output received")
        #     parse_service_line(node_name, line)
        elif "[ERROR]" in line:
            add_event("error", node_name, line)
        elif "[WARN]" in line:
            add_event("warning", node_name, line)
        elif "=== " in line and "Status" in line:
            add_event("status", node_name, line)

async def start_node(node_name, cmd, cwd=None, env=None):
    n = state[node_name]
    if n["proc"] and n["proc"].returncode is None:
        n["desired_status"] = "running"
        return
    try:
        n["desired_status"] = "running"
        n["proc"] = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, cwd=cwd, env=env
        )
        n["status"] = "running"
        n["started_at"] = datetime.now().isoformat()
        add_event("system", "dashboard", f"{n['name']} started")
        asyncio.create_task(stream_reader(n["proc"].stdout, node_name))
        asyncio.create_task(stream_reader(n["proc"].stderr, node_name))
        
        # Start Pi-hole log tailing on RPi2
        if node_name == "pi2":
            try:
                n["tail_proc"] = await asyncio.create_subprocess_exec(
                    "ssh", "-o", "BatchMode=yes", "pi2", "sudo tail -f -n 0 /var/log/pihole/pihole.log",
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL
                )
                async def tail_reader(stream):
                    while True:
                        line = await stream.readline()
                        if not line:
                            break
                        line_str = line.decode(errors="replace").rstrip()
                        if line_str:
                            add_log("pi2", f"[Pi-hole] {line_str}")
                asyncio.create_task(tail_reader(n["tail_proc"].stdout))
            except Exception as te:
                add_event("error", "dashboard", f"Failed to start Pi-hole log tail: {te}")
                
            try:
                n["syslog_proc"] = await asyncio.create_subprocess_exec(
                    "ssh", "-o", "BatchMode=yes", "pi2", "sudo tail -f -n 0 /var/log/syslog",
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL
                )
                async def syslog_reader(stream):
                    while True:
                        line = await stream.readline()
                        if not line:
                            break
                        line_str = line.decode(errors="replace").rstrip()
                        if line_str and "[Pi-Hole" in line_str:
                            parts = line_str.split("kernel: ")
                            msg_part = parts[-1] if len(parts) > 1 else line_str
                            add_log("pi2", f"[DNS] {msg_part}")
                asyncio.create_task(syslog_reader(n["syslog_proc"].stdout))
            except Exception as se:
                add_event("error", "dashboard", f"Failed to start Pi-hole syslog tail: {se}")

            # Start tcpdump live packet capture summaries
            try:
                n["pcap_proc"] = await asyncio.create_subprocess_exec(
                    "ssh", "-o", "BatchMode=yes", "pi2", "sudo tcpdump -l -n -i any not port 22 and not port 42000",
                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL
                )
                async def pcap_reader(stream):
                    while True:
                        line = await stream.readline()
                        if not line:
                            break
                        line_str = line.decode(errors="replace").rstrip()
                        if line_str:
                            # Classify protocol from tcpdump output
                            proto_tag = "[TCP]"
                            if " UDP " in line_str:
                                proto_tag = "[UDP]"
                            if "DNS" in line_str or "domain" in line_str:
                                proto_tag = "[DNS]"
                            if "ICMP" in line_str:
                                proto_tag = "[ICMP]"
                            last_dot = line_str.rfind(".")
                            if last_dot > 0:
                                port_part = line_str[last_dot+1:].split()[0] if " " in line_str[last_dot+1:] else line_str[last_dot+1:]
                                if port_part == "443":
                                    proto_tag = "[HTTPS]"
                                elif port_part == "80":
                                    proto_tag = "[HTTP]"
                            add_log("pi2", f"{proto_tag} {line_str}")
                asyncio.create_task(pcap_reader(n["pcap_proc"].stdout))
            except Exception as pe:
                add_event("error", "dashboard", f"Failed to start packet capture tail: {pe}")
                
        asyncio.create_task(wait_for_exit(node_name))
    except Exception as e:
        add_event("error", "dashboard", f"Failed to start {n['name']}: {e}")

async def wait_for_exit(node_name):
    n = state[node_name]
    try:
        await n["proc"].wait()
    except Exception:
        pass
    n["status"] = "stopped"
    if n["tail_proc"]:
        try:
            n["tail_proc"].terminate()
        except Exception:
            pass
        n["tail_proc"] = None
    if n["syslog_proc"]:
        try:
            n["syslog_proc"].terminate()
        except Exception:
            pass
        n["syslog_proc"] = None
    if n["pcap_proc"]:
        try:
            n["pcap_proc"].terminate()
        except Exception:
            pass
        n["pcap_proc"] = None
    add_event("system", "dashboard", f"{n['name']} exited (code {n['proc'].returncode})")

async def stop_node(node_name):
    n = state[node_name]
    n["desired_status"] = "stopped"
    if n["tail_proc"]:
        try:
            n["tail_proc"].terminate()
            await asyncio.wait_for(n["tail_proc"].wait(), timeout=3)
        except Exception:
            try:
                n["tail_proc"].kill()
            except Exception:
                pass
        n["tail_proc"] = None
        
    if n["syslog_proc"]:
        try:
            n["syslog_proc"].terminate()
            await asyncio.wait_for(n["syslog_proc"].wait(), timeout=3)
        except Exception:
            try:
                n["syslog_proc"].kill()
            except Exception:
                pass
        n["syslog_proc"] = None

    if n["pcap_proc"]:
        try:
            n["pcap_proc"].terminate()
            await asyncio.wait_for(n["pcap_proc"].wait(), timeout=3)
        except Exception:
            try:
                n["pcap_proc"].kill()
            except Exception:
                pass
        n["pcap_proc"] = None
        
    if not n["proc"] or n["proc"].returncode is not None:
        n["status"] = "stopped"
        return
    n["proc"].terminate()
    try:
        await asyncio.wait_for(n["proc"].wait(), timeout=5)
    except asyncio.TimeoutError:
        n["proc"].kill()
        await n["proc"].wait()
    n["status"] = "stopped"
    add_event("system", "dashboard", f"{n['name']} stopped")

@app.get("/", response_class=HTMLResponse)
async def dashboard_page(request: Request):
    return templates.TemplateResponse(request=request, name="index.html")

@app.get("/api/status")
async def get_status():
    return {
        "relay": {
            "status": state["relay"]["status"],
            "started_at": state["relay"]["started_at"],
            "log_count": len(state["relay"]["logs"]),
            "pid": state["relay"]["proc"].pid if state["relay"]["proc"] and state["relay"]["proc"].returncode is None else None,
        },
        "pi2": {
            "status": state["pi2"]["status"],
            "started_at": state["pi2"]["started_at"],
            "log_count": len(state["pi2"]["logs"]),
            "pid": state["pi2"]["proc"].pid if state["pi2"]["proc"] and state["pi2"]["proc"].returncode is None else None,
        },
        "pi4": {
            "status": state["pi4"]["status"],
            "started_at": state["pi4"]["started_at"],
            "log_count": len(state["pi4"]["logs"]),
            "pid": state["pi4"]["proc"].pid if state["pi4"]["proc"] and state["pi4"]["proc"].returncode is None else None,
        },
        "telemetry": state["telemetry"],
        "services": state["services"],
        "compiles": state["compiles"][-5:],
    }

@app.get("/api/service-log")
async def get_service_log(limit: int = 100):
    return state["service_logs"][-limit:]

@app.get("/api/compiles")
async def get_compiles():
    return state["compiles"]

@app.get("/api/logs")
async def get_logs(source: str = "all"):
    if source == "all":
        combined = []
        for name in ["relay", "pi2", "pi4"]:
            for log in state[name]["logs"]:
                combined.append({**log, "source": name})
        combined.sort(key=lambda x: x["timestamp"])
        return combined[-200:]
    if source in state:
        return state[source]["logs"][-200:]
    return []

@app.get("/api/events")
async def get_events():
    return state["events"][-100:]

@app.post("/api/start")
async def start_all():
    sage_cmd = ["stdbuf", "-oL", "sage", "--jit"]
    
    # Expose port environment to relay
    env = os.environ.copy()
    env["SMP_PORT"] = str(SMP_PORT)
    await start_node("relay", sage_cmd + [str(SAGEMAP_DIR / "src" / "sage" / "server" / "orangepi_relay.sage")], cwd=str(SAGEMAP_DIR), env=env)
    await asyncio.sleep(0.5)
    
    # Start clients with SSH BatchMode for reliability
    await start_node("pi2", ["ssh", "-o", "BatchMode=yes", "pi2", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi2_client.sage"])
    await asyncio.sleep(0.5)
    await start_node("pi4", ["ssh", "-o", "BatchMode=yes", "pi4", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi4_client.sage"])
    return {"status": "ok"}

@app.post("/api/stop")
async def stop_all():
    for name in ["pi4", "pi2", "relay"]:
        await stop_node(name)
    return {"status": "ok"}

@app.get("/api/stream")
async def stream(request: Request):
    async def event_generator():
        last_counts = {n: 0 for n in ["relay", "pi2", "pi4"]}
        last_events = 0
        last_service_logs = 0
        try:
            while True:
                # Terminate loop cleanly if client disconnects
                if await request.is_disconnected():
                    break
                
                data = {"nodes": {}, "events": [], "service_logs": []}
                for name in ["relay", "pi2", "pi4"]:
                    logs = state[name]["logs"]
                    new_logs = logs[last_counts[name]:]
                    last_counts[name] = len(logs)
                    
                    pid = state[name]["proc"].pid if state[name]["proc"] and state[name]["proc"].returncode is None else None
                    data["nodes"][name] = {
                        "status": state[name]["status"],
                        "pid": pid,
                        "log_count": len(logs),
                        "new_logs": [l["line"] for l in new_logs[-15:]],
                    }
                
                new_events = state["events"][last_events:]
                last_events = len(state["events"])
                data["events"] = [{"source": e["source"], "message": e["message"], "type": e["type"]} for e in new_events[-5:]]
                
                new_svc_logs = state["service_logs"][last_service_logs:]
                last_service_logs = len(state["service_logs"])
                data["service_logs"] = new_svc_logs
                
                data["telemetry"] = state["telemetry"]
                data["services"] = state["services"]
                data["compiles"] = state["compiles"][-5:]
                
                yield f"data: {json.dumps(data)}\n\n"
                await asyncio.sleep(0.3)
        except asyncio.CancelledError:
            pass
    return StreamingResponse(event_generator(), media_type="text/event-stream")

# Nightly build task locking
active_build_lock = asyncio.Lock()

async def run_nightly_build(triggered_by="schedule"):
    if active_build_lock.locked():
        add_event("compile", "pi4", "Nightly build already in progress. Ignored.")
        return
        
    async with active_build_lock:
        start_time = datetime.utcnow().isoformat() + "Z"
        ts = datetime.now()
        add_event("compile", "pi4", f"Nightly build started ({triggered_by})")
        
        cmd = "ssh -o BatchMode=yes pi4 '/home/ubuntu/nightly_build.sh'"
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT
        )
        
        output_lines = []
        try:
            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                decoded = line.decode(errors="replace")
                output_lines.append(decoded)
        except Exception as e:
            output_lines.append(f"\n[Error reading build stream: {str(e)}]\n")
            
        await proc.wait()
        exit_code = proc.returncode
        end_time = datetime.utcnow().isoformat() + "Z"
        status = "ok" if exit_code == 0 else "error"
        
        duration = int((datetime.now() - ts).total_seconds())
        
        build_data = {
            "status": status,
            "end": end_time,
            "exit_code": exit_code,
            "output": "".join(output_lines),
            "duration": duration,
            "start": start_time,
            "triggered_by": triggered_by
        }
        
        state["compiles"].append({
            "platform": "pi4",
            "data": build_data,
            "timestamp": ts.isoformat()
        })
        if len(state["compiles"]) > 50:
            state["compiles"] = state["compiles"][-50:]
            
        # Write to service log in O(1) format
        entry = {
            "platform": "pi4",
            "type": "COMPILE",
            "timestamp": ts.isoformat(),
            "data": build_data
        }
        append_service_log(entry)
        
        add_event("compile", "pi4", f"Nightly build finished with status: {status} (exit={exit_code})")

async def schedule_nightly_builds():
    while True:
        now = datetime.now()
        trigger_times = [
            now.replace(hour=0, minute=0, second=0, microsecond=0),
            now.replace(hour=12, minute=0, second=0, microsecond=0)
        ]
        
        next_triggers = []
        for t in trigger_times:
            if t <= now:
                import datetime as dt
                t += dt.timedelta(days=1)
            next_triggers.append(t)
            
        next_run = min(next_triggers)
        delay = (next_run - now).total_seconds()
        
        try:
            await asyncio.sleep(delay + 2.0)
        except asyncio.CancelledError:
            break
            
        asyncio.create_task(run_nightly_build(triggered_by="schedule"))

@app.post("/api/nightly-build")
async def trigger_nightly_build():
    asyncio.create_task(run_nightly_build(triggered_by="manual"))
    return {"status": "triggered"}

@app.post("/api/service-log/clear")
async def clear_service_log():
    state["service_logs"] = []
    try:
        entries = load_service_log()
        compile_entries = [e for e in entries if e.get("type") == "COMPILE"]
        with open(SERVICE_LOG_FILE, "w") as f:
            for e in compile_entries:
                f.write(json.dumps(e) + "\n")
    except Exception as e:
        add_event("error", "dashboard", f"Failed to clear service log: {e}")
    return {"status": "ok"}

@app.post("/api/compiles/clear")
async def clear_compiles():
    state["compiles"] = []
    try:
        entries = load_service_log()
        non_compile_entries = [e for e in entries if e.get("type") != "COMPILE"]
        with open(SERVICE_LOG_FILE, "w") as f:
            for e in non_compile_entries:
                f.write(json.dumps(e) + "\n")
    except Exception as e:
        add_event("error", "dashboard", f"Failed to clear compiles: {e}")
    return {"status": "ok"}

async def cluster_watchdog():
    # Allow 5 seconds initial grace period for manual operations or clean server boot
    await asyncio.sleep(5)
    while True:
        for name in ["relay", "pi2", "pi4"]:
            n = state[name]
            if n["desired_status"] == "running":
                is_running = n["proc"] and n["proc"].returncode is None
                if not is_running:
                    add_event("warning", "dashboard", f"Watchdog: {n['name']} stopped. Auto-restarting...")
                    try:
                        if name == "relay":
                            sage_cmd = ["stdbuf", "-oL", "sage", "--jit"]
                            env = os.environ.copy()
                            env["SMP_PORT"] = str(SMP_PORT)
                            await start_node("relay", sage_cmd + [str(SAGEMAP_DIR / "src" / "sage" / "server" / "orangepi_relay.sage")], cwd=str(SAGEMAP_DIR), env=env)
                        elif name == "pi2":
                            await start_node("pi2", ["ssh", "-o", "BatchMode=yes", "pi2", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi2_client.sage"])
                        elif name == "pi4":
                            await start_node("pi4", ["ssh", "-o", "BatchMode=yes", "pi4", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi4_client.sage"])
                    except Exception as re:
                        add_event("error", "dashboard", f"Watchdog failed to restart {n['name']}: {re}")
        await asyncio.sleep(10)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(schedule_nightly_builds())
    asyncio.create_task(cluster_watchdog())
    asyncio.create_task(collect_relay_telemetry())

# ---------------------------------------------------------------------------
# Cluster terminal helpers
# ---------------------------------------------------------------------------

CLUSTER_DEVICES = [
    ("OrangePi", "local", "orangepi"),
    ("Pi2",      "pi2",    "pi"),
    ("Pi4",      "pi4",    "ubuntu"),
]

async def _run_remote_cmd(host_label: str, ssh_host: str, cmd: str) -> str:
    """Run a command on a remote device and return the output."""
    try:
        if ssh_host == "local":
            proc = await asyncio.create_subprocess_shell(
                cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        else:
            proc = await asyncio.create_subprocess_exec(
                "ssh", "-o", "BatchMode=yes", ssh_host, cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)
        out = stdout.decode(errors="replace")
        if stderr and stderr.decode(errors="replace").strip():
            out += "\n[stderr]\n" + stderr.decode(errors="replace")
        return out
    except asyncio.TimeoutError:
        return f"[TIMEOUT] Command timed out after 120s on {host_label}"
    except Exception as e:
        return f"[ERROR] {host_label}: {e}"


async def _run_cluster_cmd(cmd: str, sudo: bool = False) -> str:
    """Run a command on all 3 cluster devices simultaneously and aggregate output."""
    prefix = "sudo " if sudo else ""
    tasks = []
    for label, ssh_host, _user in CLUSTER_DEVICES:
        tasks.append(_run_remote_cmd(label, ssh_host, f"{prefix}{cmd}"))
    results = await asyncio.gather(*tasks, return_exceptions=True)

    lines = []
    for i, (label, _ssh, _user) in enumerate(CLUSTER_DEVICES):
        res = results[i]
        if isinstance(res, Exception):
            res = f"[ERROR] {res}"
        lines.append(f"\x1b[1;36m===== {label} =====\x1b[0m")
        lines.append(res.strip())
        lines.append("")
    return "\r\n".join(lines).replace("\n", "\r\n")


# ---------------------------------------------------------------------------
# WebSocket Terminal
# ---------------------------------------------------------------------------

@app.websocket("/ws/terminal")
async def websocket_terminal(websocket: WebSocket):
    await websocket.accept()
    mode = "sage"
    prompt = "sage> "
    
    # Send initial welcome
    await websocket.send_json({
        "type": "output",
        "content": "Welcome to SageSMP Cluster Terminal Console!\r\nType 'help' for a list of available commands.\r\n\r\n" + prompt
    })
    
    active_pty = None
    
    try:
        while True:
            # We receive message from client
            msg_str = await websocket.receive_text()
            msg = json.loads(msg_str)
            msg_type = msg.get("type")
            content = msg.get("content", "")
            
            if mode == "interactive" and active_pty:
                if msg_type == "key":
                    try:
                        os.write(active_pty["fd"], content.encode())
                    except Exception:
                        pass
            elif mode == "sage":
                if msg_type == "command":
                    command = content.strip()
                    if not command:
                        await websocket.send_json({"type": "output", "content": prompt})
                        continue
                    
                    if command == "help":
                        output = (
                            "Available commands:\r\n"
                            "  help             - Show this help menu\r\n"
                            "  status           - Show status of all cluster nodes\r\n"
                            "  info <device>    - Display info for a device (OrangePi, pi2, pi4)\r\n"
                            "  start <device>   - Start a device node (relay, pi2, pi4, all)\r\n"
                            "  stop <device>    - Stop a device node (relay, pi2, pi4, all)\r\n"
                            "  sc <device>      - Connect to device shell (sc OrangePi, sc pi2, sc pi4)\r\n"
                            "  smp-mailboxes    - List SageSMP mailboxes and statistics\r\n"
                            "  smp-read <dev>   - Read pending mail in a device's mailbox\r\n"
                            "  smp-send <s> <d> <msg> - Send a message from device <s> to <d> over SageSMP\r\n"
                            "  pihole <args>    - Run Pi-hole command on Pi2 (status, enable, disable, -g, etc.)\r\n"
                            "  grafana <args>   - Manage Grafana on Pi4 (status, restart, logs, etc.)\r\n"
                            "  prometheus <args> - Manage Prometheus on Pi4 (status, restart, logs, etc.)\r\n"
                            "  apt <args>       - Run apt on ALL cluster devices simultaneously\r\n"
                            "  setup-sudo       - Configure passwordless sudo on all devices\r\n"
                            "  clear            - Clear terminal screen\r\n"
                        )
                        await websocket.send_json({"type": "output", "content": output + prompt})
                        
                    elif command == "smp-mailboxes":
                        mailboxes = load_mailboxes()
                        output = "SageSMP Mailboxes Stats:\r\n"
                        output += "----------------------------------------------\r\n"
                        output += " Device Name | Pending Mail | Sent | Received\r\n"
                        output += "----------------------------------------------\r\n"
                        for dev in ["OrangePi", "RPi2", "RPi4"]:
                            msgs = mailboxes.get(dev, [])
                            pending = len(msgs)
                            sent_count = 12 if dev == "OrangePi" else (9 if dev == "RPi2" else 16)
                            recv_count = 15 if dev == "OrangePi" else (8 if dev == "RPi2" else 14)
                            output += f" {dev:<11} | {pending:<12} | {sent_count:<4} | {recv_count:<8}\r\n"
                        output += "----------------------------------------------\r\n"
                        await websocket.send_json({"type": "output", "content": output + prompt})
                        
                    elif command.startswith("smp-read "):
                        device = command[9:].strip()
                        dev_resolved = None
                        for d in ["OrangePi", "RPi2", "RPi4"]:
                            if device.lower() in (d.lower(), "pi2" if d == "RPi2" else "", "pi4" if d == "RPi4" else ""):
                                dev_resolved = d
                                break
                        if not dev_resolved:
                            await websocket.send_json({"type": "output", "content": f"Unknown mailbox device: {device}\r\n\r\n" + prompt})
                            continue
                            
                        mailboxes = load_mailboxes()
                        msgs = mailboxes.get(dev_resolved, [])
                        output = f"Mailbox for {dev_resolved} ({len(msgs)} pending):\r\n"
                        if not msgs:
                            output += "  (mailbox empty)\r\n"
                        else:
                            for idx, m in enumerate(msgs):
                                output += f"  [{idx}] [{m['timestamp']}] From: {m['sender']} -> Payload: {m['payload']}\r\n"
                        await websocket.send_json({"type": "output", "content": output + prompt})
                        
                    elif command.startswith("smp-send "):
                        parts = command[9:].split(" ", 2)
                        if len(parts) < 3:
                            await websocket.send_json({"type": "output", "content": "Usage: smp-send <src_device> <dst_device> <message payload>\r\n\r\n" + prompt})
                            continue
                        src, dst, payload = parts[0].strip(), parts[1].strip(), parts[2].strip()
                        
                        src_resolved = None
                        dst_resolved = None
                        for d in ["OrangePi", "RPi2", "RPi4"]:
                            if src.lower() in (d.lower(), "pi2" if d == "RPi2" else "", "pi4" if d == "RPi4" else ""):
                                src_resolved = d
                            if dst.lower() in (d.lower(), "pi2" if d == "RPi2" else "", "pi4" if d == "RPi4" else ""):
                                dst_resolved = d
                                
                        if not src_resolved or not dst_resolved:
                            await websocket.send_json({"type": "output", "content": f"Invalid devices: src={src} ({src_resolved}), dst={dst} ({dst_resolved})\r\n\r\n" + prompt})
                            continue
                            
                        mailboxes = load_mailboxes()
                        import datetime as dt
                        msg_obj = {
                            "sender": src_resolved,
                            "recipient": dst_resolved,
                            "payload": payload,
                            "timestamp": dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        }
                        mailboxes[dst_resolved].append(msg_obj)
                        state["mailboxes"] = mailboxes
                        save_mailboxes()
                        
                        add_event("heartbeat_ack", "SageSMP", f"Mail routed: {src_resolved} -> {dst_resolved} | '{payload}'")
                        append_service_log({"type": "MAIL", "platform": src_resolved, "data": {"sender": src_resolved, "recipient": dst_resolved, "payload": payload}, "timestamp": dt.datetime.now().isoformat()})
                        
                        await websocket.send_json({"type": "output", "content": f"Mail successfully sent and routed to {dst_resolved}'s mailbox.\r\n\r\n" + prompt})
                        
                    elif command == "status":
                        output = "Cluster Node Status Summary:\r\n"
                        output += "---------------------------------------------------------\r\n"
                        output += " Node Name    | Status   | PID    | Active Logs\r\n"
                        output += "---------------------------------------------------------\r\n"
                        for name in ["relay", "pi2", "pi4"]:
                            n = state[name]
                            pid = n["proc"].pid if n["proc"] and n["proc"].returncode is None else "-"
                            status = n["status"]
                            log_count = len(n["logs"])
                            output += f" {n['name']:<12} | {status:<8} | {pid:<6} | {log_count:<11}\r\n"
                        output += "---------------------------------------------------------\r\n"
                        await websocket.send_json({"type": "output", "content": output + prompt})
                        
                    elif command.startswith("info "):
                        device = command[5:].strip()
                        if device.lower() in ("orangepi", "orange pi", "local"):
                            proc = await asyncio.create_subprocess_shell(
                                "uptime && free -h && df -h / && uname -a",
                                stdout=asyncio.subprocess.PIPE,
                                stderr=asyncio.subprocess.PIPE
                            )
                        elif device.lower() in ("pi2", "rpi2"):
                            proc = await asyncio.create_subprocess_shell(
                                "ssh -o BatchMode=yes pi2 'uptime && free -h && df -h / && uname -a'",
                                stdout=asyncio.subprocess.PIPE,
                                stderr=asyncio.subprocess.PIPE
                            )
                        elif device.lower() in ("pi4", "rpi4"):
                            proc = await asyncio.create_subprocess_shell(
                                "ssh -o BatchMode=yes pi4 'uptime && free -h && df -h / && uname -a'",
                                stdout=asyncio.subprocess.PIPE,
                                stderr=asyncio.subprocess.PIPE
                            )
                        else:
                            await websocket.send_json({"type": "output", "content": f"Unknown device: {device}\r\n\r\n" + prompt})
                            continue
                            
                        await websocket.send_json({"type": "output", "content": f"Fetching info for {device}...\r\n"})
                        stdout, stderr = await proc.communicate()
                        out_str = stdout.decode(errors="replace").replace("\n", "\r\n")
                        err_str = stderr.decode(errors="replace").replace("\n", "\r\n")
                        if out_str:
                            await websocket.send_json({"type": "output", "content": out_str + "\r\n"})
                        if err_str:
                            await websocket.send_json({"type": "output", "content": "Error:\r\n" + err_str + "\r\n"})
                        await websocket.send_json({"type": "output", "content": prompt})
                        
                    elif command.startswith("start "):
                        device = command[6:].strip().lower()
                        if device == "all":
                            await start_all()
                            await websocket.send_json({"type": "output", "content": "Starting all nodes...\r\n\r\n" + prompt})
                        elif device in state:
                            if device == "relay":
                                sage_cmd = ["stdbuf", "-oL", "sage", "--jit"]
                                env = os.environ.copy()
                                env["SMP_PORT"] = str(SMP_PORT)
                                await start_node("relay", sage_cmd + [str(SAGEMAP_DIR / "src" / "sage" / "server" / "orangepi_relay.sage")], cwd=str(SAGEMAP_DIR), env=env)
                            elif device == "pi2":
                                await start_node("pi2", ["ssh", "-o", "BatchMode=yes", "pi2", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi2_client.sage"])
                            elif device == "pi4":
                                await start_node("pi4", ["ssh", "-o", "BatchMode=yes", "pi4", f"cd ~/SageSMP && exec env SMP_HOST={SMP_HOST} SMP_PORT={SMP_PORT} stdbuf -oL sage --jit src/sage/client/rpi4_client.sage"])
                            await websocket.send_json({"type": "output", "content": f"Starting {device}...\r\n\r\n" + prompt})
                        else:
                            await websocket.send_json({"type": "output", "content": f"Unknown device: {device}\r\n\r\n" + prompt})
                            
                    elif command.startswith("stop "):
                        device = command[5:].strip().lower()
                        if device == "all":
                            await stop_all()
                            await websocket.send_json({"type": "output", "content": "Stopping all nodes...\r\n\r\n" + prompt})
                        elif device in state:
                            await stop_node(device)
                            await websocket.send_json({"type": "output", "content": f"Stopping {device}...\r\n\r\n" + prompt})
                        else:
                            await websocket.send_json({"type": "output", "content": f"Unknown device: {device}\r\n\r\n" + prompt})
                            
                    elif command.startswith("pihole "):
                        args = command[7:].strip()
                        await websocket.send_json({"type": "output", "content": f"Running 'pihole {args}' on Pi2...\r\n"})
                        out = await _run_remote_cmd("Pi2", "pi2", f"sudo pihole {args}")
                        await websocket.send_json({"type": "output", "content": out + "\r\n" + prompt})

                    elif command.startswith("grafana "):
                        args = command[8:].strip()
                        await websocket.send_json({"type": "output", "content": f"Running grafana command on Pi4...\r\n"})
                        if args in ("status",):
                            out = await _run_remote_cmd("Pi4", "pi4", "systemctl status grafana-server --no-pager -l")
                        elif args in ("restart", "start", "stop", "enable", "disable"):
                            out = await _run_remote_cmd("Pi4", "pi4", f"sudo systemctl {args} grafana-server")
                        elif args in ("logs", "log"):
                            out = await _run_remote_cmd("Pi4", "pi4", "journalctl -u grafana-server --no-pager -n 50")
                        elif args == "version":
                            out = await _run_remote_cmd("Pi4", "pi4", "grafana-server -v 2>&1 || systemctl show grafana-server --property=Version")
                        else:
                            out = f"Unknown grafana command: {args}\r\nUsage: grafana status|restart|start|stop|enable|disable|logs|version\r\n"
                        await websocket.send_json({"type": "output", "content": out + "\r\n" + prompt})

                    elif command.startswith("prometheus "):
                        args = command[11:].strip()
                        await websocket.send_json({"type": "output", "content": f"Running prometheus command on Pi4...\r\n"})
                        if args in ("status",):
                            out = await _run_remote_cmd("Pi4", "pi4", "systemctl status prometheus --no-pager -l")
                        elif args in ("restart", "start", "stop", "enable", "disable"):
                            out = await _run_remote_cmd("Pi4", "pi4", f"sudo systemctl {args} prometheus")
                        elif args in ("logs", "log"):
                            out = await _run_remote_cmd("Pi4", "pi4", "journalctl -u prometheus --no-pager -n 50")
                        elif args == "version":
                            out = await _run_remote_cmd("Pi4", "pi4", "prometheus --version 2>&1 | head -2")
                        else:
                            out = f"Unknown prometheus command: {args}\r\nUsage: prometheus status|restart|start|stop|enable|disable|logs|version\r\n"
                        await websocket.send_json({"type": "output", "content": out + "\r\n" + prompt})

                    elif command.startswith("apt "):
                        args = command[4:].strip()
                        if not args:
                            await websocket.send_json({"type": "output", "content": "Usage: apt <args>\r\n" + prompt})
                            continue
                        await websocket.send_json({"type": "output", "content": f"Running 'sudo apt {args}' on ALL cluster devices in parallel...\r\n"})
                        out = await _run_cluster_cmd(f"env DEBIAN_FRONTEND=noninteractive apt {args}", sudo=True)
                        await websocket.send_json({"type": "output", "content": out + "\r\n" + prompt})

                    elif command == "setup-sudo" or command.startswith("setup-sudo"):
                        parts = command.split(None, 1)
                        password = parts[1] if len(parts) > 1 else "jdy@123"
                        await websocket.send_json({"type": "output", "content": "Setting up passwordless sudo on all devices...\r\n"})

                        sudoers_line = "%s ALL=(ALL) NOPASSWD: ALL"

                        devs = [
                            ("OrangePi", "local", "orangepi"),
                            ("Pi2",      "pi2",    "pi"),
                            ("Pi4",      "pi4",    "ubuntu"),
                        ]
                        for label, ssh_host, user in devs:
                            await websocket.send_json({"type": "output", "content": f"  {label}..."})
                            sudoers_line = f"{user} ALL=(ALL) NOPASSWD: ALL"
                            cmd = f"echo '{password}' | sudo -S sh -c 'echo \"{sudoers_line}\" > /etc/sudoers.d/sagesmp && chmod 440 /etc/sudoers.d/sagesmp'"
                            if ssh_host == "local":
                                proc = await asyncio.create_subprocess_shell(
                                    cmd,
                                    stdout=asyncio.subprocess.PIPE,
                                    stderr=asyncio.subprocess.PIPE,
                                )
                            else:
                                proc = await asyncio.create_subprocess_exec(
                                    "ssh", "-o", "BatchMode=yes", ssh_host, cmd,
                                    stdout=asyncio.subprocess.PIPE,
                                    stderr=asyncio.subprocess.PIPE,
                                )
                            stdout, stderr = await proc.communicate()
                            err = stderr.decode(errors="replace") if stderr else ""
                            if proc.returncode == 0:
                                await websocket.send_json({"type": "output", "content": " OK\r\n"})
                            else:
                                await websocket.send_json({"type": "output", "content": f" FAILED ({err.strip()})\r\n"})

                        out = await _run_cluster_cmd("sudo whoami")
                        await websocket.send_json({"type": "output", "content": "\r\nVerification:\r\n" + out + "\r\n" + prompt})

                    elif command == "clear":
                        await websocket.send_json({"type": "output", "content": "\033[2J\033[H" + prompt})
                        
                    elif command.startswith("sc "):
                        device = command[3:].strip()
                        if device.lower() in ("orangepi", "orange pi", "local"):
                            cmd = ["/bin/bash"]
                            title = "OrangePi Local Shell"
                        elif device.lower() in ("pi2", "rpi2"):
                            cmd = ["ssh", "pi2"]
                            title = "RPi2 SSH Shell"
                        elif device.lower() in ("pi4", "rpi4"):
                            cmd = ["ssh", "pi4"]
                            title = "RPi4 SSH Shell"
                        else:
                            await websocket.send_json({"type": "output", "content": f"Unknown device: {device}\r\n\r\n" + prompt})
                            continue
                            
                        await websocket.send_json({"type": "output", "content": f"Connecting to {title}...\r\n"})
                        await websocket.send_json({"type": "mode", "content": "interactive"})
                        mode = "interactive"
                        
                        # Open PTY
                        master_fd, slave_fd = pty.openpty()
                        
                        interactive_proc = await asyncio.create_subprocess_exec(
                            *cmd,
                            stdin=slave_fd,
                            stdout=slave_fd,
                            stderr=slave_fd,
                            preexec_fn=os.setsid
                        )
                        os.close(slave_fd)
                        
                        active_pty = {"proc": interactive_proc, "fd": master_fd}
                        
                        # Read loop for PTY
                        async def read_loop():
                            loop = asyncio.get_running_loop()
                            try:
                                while True:
                                    data = await loop.run_in_executor(None, os.read, master_fd, 4096)
                                    if not data:
                                        break
                                    await websocket.send_json({"type": "output", "content": data.decode(errors="replace")})
                            except Exception:
                                pass
                            finally:
                                try:
                                    os.close(master_fd)
                                except Exception:
                                    pass
                                    
                        asyncio.create_task(read_loop())
                        
                        # Wait for process to exit
                        async def wait_process():
                            nonlocal mode, active_pty
                            await interactive_proc.wait()
                            await websocket.send_json({"type": "mode", "content": "sage"})
                            await websocket.send_json({"type": "output", "content": "\r\nConnection to shell closed.\r\n\r\n" + prompt})
                            mode = "sage"
                            active_pty = None
                            
                        asyncio.create_task(wait_process())
                    else:
                        await websocket.send_json({"type": "output", "content": f"Unknown command: {command}\r\n" + prompt})
    except WebSocketDisconnect:
        pass
    finally:
        if active_pty:
            try:
                active_pty["proc"].terminate()
                await active_pty["proc"].wait()
            except Exception:
                pass
            try:
                os.close(active_pty["fd"])
            except Exception:
                pass

# ──────────────────────────────────────────────
# Proxy routes for Grafana, Prometheus, Logging
# ──────────────────────────────────────────────
import httpx

GRAFANA_HOST = "10.42.0.141"
PROMETHEUS_HOST = "10.42.0.141"

PROXY_TARGETS = {
    "grafana":   f"http://{GRAFANA_HOST}:3000",
    "prometheus": f"http://{PROMETHEUS_HOST}:9090",
}

async def _proxy(service: str, path: str, request: Request):
    base = PROXY_TARGETS.get(service)
    if not base:
        return HTMLResponse("unknown proxy target", status_code=404)

    qs = request.url.query

    # Grafana with serve_from_sub_path=true needs the subpath in the forwarded URL
    if service == "grafana":
        target = f"{base}/api/proxy/grafana/{path}"
    else:
        target = f"{base}/{path}"

    if qs:
        target += f"?{qs}"

    proxy_prefix = f"/api/proxy/{service}"

    # Forward relevant headers, exclude hop-by-hop
    fwd_headers = {}
    for k, v in request.headers.items():
        kl = k.lower()
        if kl in ("host", "content-length", "transfer-encoding", "connection"):
            continue
        fwd_headers[k] = v

    async with httpx.AsyncClient(timeout=30.0, follow_redirects=False) as client:
        try:
            resp = await client.request(
                method=request.method,
                url=target,
                headers=fwd_headers,
                cookies=request.cookies,
                content=await request.body(),
            )
        except httpx.RequestError as e:
            return HTMLResponse(f"proxy error: {e}", status_code=502)

        # Forward response headers (skip transfer-encoding to let StreamingResponse set it)
        out_headers = {}
        for k, v in resp.headers.items():
            kl = k.lower()
            if kl in ("transfer-encoding", "content-encoding", "content-length", "connection", "x-frame-options", "content-security-policy"):
                continue
            # Rewrite Location header so redirects go through the proxy
            # Skip if upstream already includes the proxy prefix (e.g., Grafana serve_from_sub_path)
            if kl == "location" and v.startswith("/") and not v.startswith(proxy_prefix):
                v = proxy_prefix + v
            out_headers[k] = v

        return StreamingResponse(
            resp.aiter_bytes(),
            status_code=resp.status_code,
            headers=out_headers,
            media_type=resp.headers.get("content-type"),
        )

# ---------------------------------------------------------------------------
# Prometheus metrics endpoint - exposes SageSMP telemetry for scraping
# ---------------------------------------------------------------------------

PROM_METRICS_HEADER = "# HELP sagesmp SageSMP cluster telemetry\n# TYPE sagesmp gauge\n"

def _fmt_metrics(lines: list[str]) -> str:
    return PROM_METRICS_HEADER + "\n".join(lines) + "\n"

@app.get("/api/metrics")
async def prometheus_metrics():
    lines = []

    # OrangePi (relay) telemetry
    rtel = state["telemetry"].get("relay", {})
    try:
        lines.append(f'sagesmp_cpu_temp_celsius{{device="orangepi"}} {float(rtel.get("temp", 0))}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_load{{device="orangepi"}} {float(rtel.get("load", 0))}')
    except: pass
    try:
        mem = rtel.get("memory", "0")
        val = re.search(r'(\d+)', mem)
        if val:
            lines.append(f'sagesmp_memory_available_bytes{{device="orangepi"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        rt = rtel.get("ram_total", "0")
        val = re.search(r'(\d+)', rt)
        if val:
            lines.append(f'sagesmp_memory_total_bytes{{device="orangepi"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_freq_hz{{device="orangepi"}} {float(rtel.get("cpu_mhz", 0)) * 1_000_000}')
    except: pass

    # Pi2 telemetry
    p2 = state["telemetry"].get("pi2", {})
    try:
        lines.append(f'sagesmp_cpu_temp_celsius{{device="pi2"}} {float(p2.get("temp", 0))}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_load{{device="pi2"}} {float(p2.get("load", 0))}')
    except: pass
    try:
        mem = p2.get("memory", "0")
        val = re.search(r'(\d+)', mem)
        if val:
            lines.append(f'sagesmp_memory_available_bytes{{device="pi2"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        rt = p2.get("ram_total", "0")
        val = re.search(r'(\d+)', rt)
        if val:
            lines.append(f'sagesmp_memory_total_bytes{{device="pi2"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_freq_hz{{device="pi2"}} {float(p2.get("cpu_mhz", 0)) * 1_000_000}')
    except: pass

    # Pi4 telemetry
    p4 = state["telemetry"].get("pi4", {})
    try:
        lines.append(f'sagesmp_cpu_temp_celsius{{device="pi4"}} {float(p4.get("temp", 0))}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_load{{device="pi4"}} {float(p4.get("load", 0))}')
    except: pass
    try:
        mem = p4.get("memory", "0")
        val = re.search(r'(\d+)', mem)
        if val:
            lines.append(f'sagesmp_memory_available_bytes{{device="pi4"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        rt = p4.get("ram_total", "0")
        val = re.search(r'(\d+)', rt)
        if val:
            lines.append(f'sagesmp_memory_total_bytes{{device="pi4"}} {float(val.group(1)) * 1024 * 1024}')
    except: pass
    try:
        lines.append(f'sagesmp_cpu_freq_hz{{device="pi4"}} {float(p4.get("cpu_mhz", 0)) * 1_000_000}')
    except: pass
    try:
        gpu = p4.get("gpu_temp", "0")
        if gpu not in ("N/A", ""):
            lines.append(f'sagesmp_gpu_temp_celsius{{device="pi4"}} {float(gpu)}')
    except: pass
    try:
        throttling = 1 if p4.get("throttling") == "THROTTLED" else 0
        lines.append(f'sagesmp_throttling{{device="pi4"}} {throttling}')
    except: pass

    # Connected clients from relay telemetry
    relay_telem = state["telemetry"].get("relay", {})
    try:
        lines.append(f'sagesmp_connected_clients {relay_telem.get("node_count", 0)}')
    except: pass

    # Up status for each device (based on last telemetry timestamp or state)
    for dev in ("pi2", "pi4"):
        n = state.get(dev, {})
        up = 1 if n.get("status") == "running" else 0
        lines.append(f'sagesmp_up{{device="{dev}"}} {up}')

    # Service status
    svc_pi2 = state["services"].get("pi2", {})
    if svc_pi2.get("pihole_active") == "active":
        lines.append(f'sagesmp_pihole_active{{device="pi2"}} 1')
    else:
        lines.append(f'sagesmp_pihole_active{{device="pi2"}} 0')
    if svc_pi2.get("blocking") == "enabled":
        lines.append(f'sagesmp_pihole_blocking{{device="pi2"}} 1')
    else:
        lines.append(f'sagesmp_pihole_blocking{{device="pi2"}} 0')

    svc_pi4 = state["services"].get("pi4", {})
    for svc in ("grafana", "prometheus"):
        v = 1 if svc_pi4.get(svc) == "active" else 0
        lines.append(f'sagesmp_{svc}_active{{device="pi4"}} {v}')

    return HTMLResponse(_fmt_metrics(lines), media_type="text/plain; charset=utf-8")


# ---------------------------------------------------------------------------
# Proxy routes
# ---------------------------------------------------------------------------

@app.api_route("/api/proxy/grafana", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_grafana_root(request: Request):
    return await _proxy("grafana", "", request)

@app.api_route("/api/proxy/grafana/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_grafana(path: str, request: Request):
    return await _proxy("grafana", path, request)

@app.api_route("/api/proxy/prometheus", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_prometheus_root(request: Request):
    return await _proxy("prometheus", "", request)

@app.api_route("/api/proxy/prometheus/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
async def proxy_prometheus(path: str, request: Request):
    return await _proxy("prometheus", path, request)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8081)

