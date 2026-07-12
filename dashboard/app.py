#!/usr/bin/env python3
"""SageSMP Dashboard - monitors interactions between OrangePi, RPi2, RPi4 on port 8081"""

import asyncio
import json
import os
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from fastapi.templating import Jinja2Templates
import uvicorn

app = FastAPI(title="SageSMP Dashboard")
templates = Jinja2Templates(directory=Path(__file__).parent / "templates")

SAGEMAP_DIR = Path.home() / "SageSMP"
BIN_DIR = SAGEMAP_DIR / "bin"
MAX_LOGS = 1000
MAX_EVENTS = 500

state = {
    "relay": {"name": "OrangePi Relay", "proc": None, "logs": [], "status": "stopped", "started_at": None},
    "pi2": {"name": "RPi2 Client", "proc": None, "logs": [], "status": "stopped", "started_at": None},
    "pi4": {"name": "RPi4 Client", "proc": None, "logs": [], "status": "stopped", "started_at": None},
    "events": [],
    "telemetry": {"pi2": {}, "pi4": {}},
}

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
    if "Temp:" in line:
        try:
            parts = line.split(",")
            info = {}
            for p in parts:
                p = p.strip()
                if "Temp:" in p:
                    info["temp"] = p.split(":")[1].strip().rstrip("C")
                elif "Load:" in p:
                    info["load"] = p.split(":")[1].strip()
                elif "Available:" in p:
                    info["memory"] = p.split(":")[1].strip()
                elif "GPU:" in p:
                    info["gpu_temp"] = p.split(":")[1].strip().rstrip("C")
                elif "Throttling:" in p:
                    info["throttling"] = p.split(":")[1].strip()
            if info:
                state["telemetry"][node_name] = info
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
        if "Sending to OrangePi:" in line or "Received info from client" in line:
            add_event("message", node_name, line)
            parse_telemetry(node_name, line)
        elif "Registered client" in line or "Unregistered client" in line:
            add_event("join_leave", node_name, line)
            parse_telemetry(node_name, line)
        elif "Broadcasting" in line or "Received broadcast" in line:
            add_event("broadcast", node_name, line)
        elif "Connected clients:" in line or "=== " in line:
            pass

async def start_node(node_name, cmd, cwd=None):
    n = state[node_name]
    if n["proc"] and n["proc"].returncode is None:
        return
    try:
        n["proc"] = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE, cwd=cwd
        )
        n["status"] = "running"
        n["started_at"] = datetime.now().isoformat()
        add_event("system", "dashboard", f"{n['name']} started")
        asyncio.create_task(stream_reader(n["proc"].stdout, node_name))
        asyncio.create_task(stream_reader(n["proc"].stderr, node_name))
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
    add_event("system", "dashboard", f"{n['name']} exited (code {n['proc'].returncode})")

async def stop_node(node_name):
    n = state[node_name]
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
    return templates.TemplateResponse("index.html", {"request": request})

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
    }

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
    relay_bin = BIN_DIR / "orangepi_relay"
    if relay_bin.exists():
        await start_node("relay", [str(relay_bin)], cwd=str(SAGEMAP_DIR))
    else:
        add_event("error", "dashboard", "orangepi_relay binary not found")
    await asyncio.sleep(0.3)
    await start_node("pi2", ["ssh", "pi2", "cd ~/SageSMP && exec ./bin/rpi2_client"])
    await asyncio.sleep(0.3)
    await start_node("pi4", ["ssh", "pi4", "cd ~/SageSMP && exec ./bin/rpi4_client"])
    return {"status": "ok"}

@app.post("/api/stop")
async def stop_all():
    for name in ["pi4", "pi2", "relay"]:
        await stop_node(name)
    return {"status": "ok"}

@app.get("/api/stream")
async def stream():
    async def event_generator():
        last_counts = {n: 0 for n in ["relay", "pi2", "pi4"]}
        last_events = 0
        while True:
            data = {"nodes": {}, "events": []}
            for name in ["relay", "pi2", "pi4"]:
                logs = state[name]["logs"]
                new_logs = logs[last_counts[name]:]
                last_counts[name] = len(logs)
                data["nodes"][name] = {
                    "status": state[name]["status"],
                    "new_logs": [l["line"] for l in new_logs[-15:]],
                }
            new_events = state["events"][last_events:]
            last_events = len(state["events"])
            data["events"] = [{"source": e["source"], "message": e["message"], "type": e["type"]} for e in new_events[-5:]]
            data["telemetry"] = state["telemetry"]
            yield f"data: {json.dumps(data)}\n\n"
            await asyncio.sleep(0.3)
    return StreamingResponse(event_generator(), media_type="text/event-stream")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8081)
