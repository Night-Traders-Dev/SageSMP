# SageSMP Interactive Dashboard Documentation

The SageSMP Dashboard provides a centralized, web-based control center for the distributed SageSMP cluster (OrangePi relay, RPi2 client, RPi4 client). 

This guide details the dashboard architecture, real-time Server-Sent Events (SSE) telemetry, and the interactive pseudo-terminal (PTY) command console.

---

## 1. Directory Structure

The dashboard files reside in the `dashboard/` directory of the project:
* `dashboard/app.py`: FastAPI server handling HTTP APIs, SSE event streams, process execution, and WebSocket terminal routing.
* `dashboard/templates/index.html`: Web interface styled with glassmorphic dark-mode assets, dynamic SVG topologies, and a full terminal emulator.

---

## 2. Real-Time Telemetry & SSE Stream

The dashboard eliminates background polling timers by consolidating all cluster status updates into a Server-Sent Events (SSE) stream endpoint: `/api/stream`.

Every 300ms, the server collects:
1. **Node Status**: Active states (running, stopped), PIDs, and active log line counts.
2. **Telemetry Details**: Node CPU/GPU temperatures, memory loads, and throttling alerts.
3. **Services & Build History**: Status of Pi-hole (RPi2), Grafana/Prometheus (RPi4), and cross-compilation records.
4. **Log Lines**: Real-time process stdout/stderr streams.
5. **System Events**: Cleaned, formatted alerts (e.g. heartbeat ping/acks).

All telemetry and logs are parsed on the client side to inject icons, emojis, and formatted metrics.

---

## 3. Interactive Web Terminal Console

The terminal console is built on top of WebSockets (`/ws/terminal`) and Python's `pty` (pseudo-terminal) module.

### Startup Mode: `SageShell`
On startup, the terminal is independent of all cluster processes and presents a local command line interface (`sage> `). It supports the following commands:

* **`help`**: Show the command list.
* **`status`**: Output a tabulated view of all cluster nodes (Status, PID, Log counts).
* **`info <device>`**: Stream system resource metrics (`uptime`, `free -h`, `df -h /`, `uname -a`) from the target machine (local or remote via SSH).
* **`start <device>`** / **`stop <device>`**: Run the startup/shutdown process on the OrangePi, RPi2, or RPi4.
* **`clear`**: Clear the terminal screen.

### Connection Mode: `sc` (Sage Connect)
The `sc` command establishes a raw, interactive session directly to a device shell:

```bash
sage> sc OrangePi
Connecting to OrangePi Local Shell...
orangepi@orangepi:~$ 
```

* **Routing**:
  * `sc OrangePi` / `sc local` $\rightarrow$ Spawns `/bin/bash` locally.
  * `sc pi2` $\rightarrow$ Spawns `ssh pi2` via the OrangePi.
  * `sc pi4` $\rightarrow$ Spawns `ssh pi4` via the OrangePi.
* **PTY Spawning**: The backend allocates a pseudo-terminal (`pty.openpty()`) and runs the target shell as a session leader, binding child stdin/stdout to the WebSocket. This enables running interactive commands (e.g., `htop`, text editors, or SSH credentials prompts).
* **Lifecycle**: Typing `exit` kills the shell subprocess, closes the PTY master file descriptor, and returns control to the `sage> ` prompt.
