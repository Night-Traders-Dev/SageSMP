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

---

## 4. SageLang Nightly Build Scheduler

The dashboard manages the automated nightly cross-compilation of the core `SageLang` language.

* **Timing**: Runs twice daily:
  * **Midnight** (00:00 local time)
  * **Noon** (12:00 local time)
* **Execution**: The OrangePi server connects via SSH to the RPi4 build node and executes:
  ```bash
  ssh -o BatchMode=yes pi4 '/home/ubuntu/nightly_build.sh'
  ```
  It captures the stdout and stderr streams dynamically, registering the results (duration, start/end timestamps, exit code, and complete build log) in the cross-compilation records.
* **Manual Force**: You can manually trigger the nightly build execution at any time by clicking the **Run Nightly Build** button inside the *Cross-Compile History* card on the web interface. This triggers a `POST` request to `/api/nightly-build`, running the compiler in an asynchronous background worker task.

---

## 5. Interactive Expandable Components

To keep the interface clean and concise, detailed telemetry, configuration, and logs are collapsed by default and can be expanded interactively by clicking on components:

1. **Node Cards (OrangePi, RPi2, RPi4)**:
   * Click to expand details such as listening IP, port configurations, active authorization types, environment setups, and full hardware specifications (CPU speed, Core Count, Architecture, Total RAM, GPU type, and Operating System details).
2. **Active Services**:
   * Click to expand service-specific metrics such as specific DNS port listen status, FTL process PID, Grafana versions, and active exporters.
3. **Cross-Compile History Runs**:
   * Click to toggle the full compilation logs output block (`pre` block), making it easy to review compile outputs on failure or collapse them on success.

---

## 6. SageSMP Mailbox Console Management

The console terminal supports direct cluster mailbox operations to manage, read, and route messages across devices over SageSMP:

* **`smp-mailboxes`**: Displays a tabulated status overview of all node mailboxes in the cluster (OrangePi, RPi2, RPi4), showing the number of pending/queued messages, and historical sent/received metrics.
* **`smp-read <device>`**: Reads the queue of pending mail inside the target device's mailbox. For each message, it details the index, timestamp, sender node, and payload.
* **`smp-send <src_device> <dst_device> <message>`**: Creates and sends a message from a source device to a destination device's mailbox over SageSMP. This generates a real-time event log update in the cluster events list and streams a record to the persistent service log.

*Note: The terminal console uses non-wrapping `whitespace-pre` layout with horizontal scrolling to display long commands and mailbox grids cleanly without formatting breakups.*


