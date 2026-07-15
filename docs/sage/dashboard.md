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

### Protocol Logging (Pi-hole Packet Capture)

When RPi2 client is running, the dashboard also streams real-time packet capture logs:

1. **Pi-hole DNS Logs** (`[Pi-hole]` tag) — real-time DNS queries from `/var/log/pihole/pihole.log`
2. **DNS Syslog** (`[DNS]` tag) — Pi-hole iptables kernel logs from `/var/log/syslog`
3. **Live Packet Capture** — `tcpdump -l -n` output with protocol classification tags:
   - `[TCP]` — General TCP traffic
   - `[UDP]` — General UDP traffic
   - `[DNS]` — DNS query/response packets
   - `[HTTP]` — Port 80 traffic
   - `[HTTPS]` — Port 443 traffic
   - `[ICMP]` — Ping/traceroute packets

These logs appear in the RPi2 console panel with their respective tags for easy filtering.

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

### Service Management Commands

The terminal provides shortcuts for managing cluster services:

* **`pihole <args>`**: Run Pi-hole commands directly on the Pi2 node. Examples:
  * `pihole status` — Show current Pi-hole blocking status.
  * `pihole enable` / `pihole disable` — Enable or disable ad-blocking.
  * `pihole disable 5m` — Disable blocking for 5 minutes.
  * `pihole -g` — Update Pi-hole gravity (ad lists).
  * `pihole restartdns` — Restart the DNS resolver.
  * `pihole logging on` / `pihole logging off` — Toggle DNS query logging.

* **`grafana <args>`**: Manage the Grafana instance on Pi4. Examples:
  * `grafana status` — Show Grafana service status and recent logs.
  * `grafana restart` / `grafana start` / `grafana stop` — Control the Grafana service.
  * `grafana enable` / `grafana disable` — Enable/disable service on boot.
  * `grafana logs` — Show the last 50 journald log lines for Grafana.
  * `grafana version` — Display the installed Grafana version.

* **`prometheus <args>`**: Manage the Prometheus instance on Pi4. Examples:
  * `prometheus status` — Show Prometheus service status.
  * `prometheus restart` / `prometheus start` / `prometheus stop` — Control the Prometheus service.
  * `prometheus logs` — Show the last 50 journald log lines for Prometheus.
  * `prometheus version` — Display the installed Prometheus version.

### Cluster-Wide Apt

The terminal supports running `apt` commands across all three cluster devices simultaneously:

* **`apt <args>`**: Runs `sudo apt <args>` on OrangePi, Pi2, and Pi4 in parallel. Output from each device is labeled and displayed together. Examples:
  * `apt update` — Refresh package lists on all devices.
  * `apt upgrade` — Upgrade packages on all devices.
  * `apt update && apt dist-upgrade` — Full system update across the cluster.
  * `apt install <package>` — Install a package on all three machines.

  > **Note:** Requires passwordless sudo to be configured on each device (see `setup-sudo` command).

### Passwordless Sudo Setup

* **`setup-sudo`**: Configures `NOPASSWD` sudo access on all three cluster devices by creating `/etc/sudoers.d/sagesmp`. This is required for the `apt` and service management commands to work without interactive password prompts. The default password (`jdy@123`) is used; you can provide an alternate password as an argument: `setup-sudo <password>`.

  You can also run the standalone shell script from the host machine:
  ```bash
  ./scripts/setup-sudo.sh
  ```

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
   * The OrangePi relay card displays **Connected Nodes** count alongside its own live telemetry (CPU Temp, Load, Available RAM, GPU Temp) — matching the per-client panels. Telemetry is polled locally from `/sys/class/thermal/` and `/proc/` every 2 seconds.
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

---

## 7. Prometheus & Grafana Monitoring

The dashboard exposes a Prometheus metrics endpoint at `/api/metrics` that converts SageSMP heartbeat telemetry into native Prometheus metrics. This enables the cluster's Prometheus instance (running on Pi4) to scrape SageSMP telemetry alongside standard node_exporter metrics.

### Prometheus Metrics Endpoint

**URL**: `http://<orangepi-ip>:8081/api/metrics`

The endpoint exposes the following metric families:

| Metric | Labels | Description |
|--------|--------|-------------|
| `sagesmp_cpu_temp_celsius` | `device` (orangepi, pi2, pi4) | CPU temperature from each device |
| `sagesmp_cpu_load` | `device` | CPU load average |
| `sagesmp_memory_available_bytes` | `device` | Available memory |
| `sagesmp_memory_total_bytes` | `device` | Total memory |
| `sagesmp_cpu_freq_hz` | `device` | Current CPU frequency |
| `sagesmp_gpu_temp_celsius` | `device` | GPU temperature (Pi4 only) |
| `sagesmp_throttling` | `device` | Throttling status (1=throttled, Pi4 only) |
| `sagesmp_connected_clients` | (none) | Number of clients connected to the relay |
| `sagesmp_up` | `device` | 1 if device is connected |
| `sagesmp_pihole_active` | `device` | 1 if Pi-hole is active (Pi2) |
| `sagesmp_pihole_blocking` | `device` | 1 if Pi-hole blocking is enabled (Pi2) |
| `sagesmp_grafana_active` | `device` | 1 if Grafana is active (Pi4) |
| `sagesmp_prometheus_active` | `device` | 1 if Prometheus is active (Pi4) |

All metrics are updated every 60 seconds as SageSMP heartbeats arrive from the cluster devices.

### Prometheus Configuration

Prometheus runs on **Pi4 (10.42.0.141:9090)** and is configured to scrape:

1. **SageSMP metrics**: `http://192.168.254.44:8081/api/metrics` (via `sagesmp` job)
2. **Node exporters**: Pi4 (localhost:9100), Pi2 (10.42.1.109:9100), OrangePi (10.42.0.1:9100)
3. **Prometheus itself**: localhost:9090

Configuration file: `/etc/prometheus/prometheus.yml` on Pi4.

### Node Exporters

- **Pi4 (arm64)**: `prometheus-node-exporter` package, port 9100 — already installed.
- **Pi2 (armhf)**: `prometheus-node-exporter` package, port 9100 — installed.
- **OrangePi (riscv64)**: `prometheus-node-exporter` package, port 9100 — installed from Ubuntu RISC-V repos.

### Grafana Dashboards

Grafana runs on **Pi4 (10.42.0.141:3000)** and is pre-configured with:

- **Prometheus data source**: Added via provisioning at `/etc/grafana/provisioning/datasources/prometheus.yaml`.
- **SageSMP Cluster dashboard**: Pre-built dashboard (`/d/a2lcqz/sagesmp-cluster`) with panels for:
  - CPU temperature, load, and frequency per device
  - Memory available and total per device
  - Pi-hole and Grafana/Prometheus service status
  - Node exporter system metrics (CPU, memory, disk, network)
- **Anonymous access**: Enabled (Viewer role) for embedded dashboard access through the dashboard proxy.
- **Admin credentials**: `admin` / `admin` (default).

### Accessing Grafana Dashboards

From the dashboard hamburger menu, the **Grafana** item embeds the Grafana login page via the proxy. After logging in (`admin`/`admin`), you can navigate to the **SageSMP Cluster** dashboard under the Dashboards menu, or access it directly at:

```
http://192.168.254.44:8081/api/proxy/grafana/d/a2lcqz/sagesmp-cluster

**Additional Grafana Dashboards (via file provisioning):**
- **SageSMP Per-Device Detail**: `/d/a2lcqz/sagesmp-devices`
- **Pi-hole Query Stats**: `/d/a2lcqz/sagesmp-pihole`

**Accessing Per-Device & Pi-hole dashboards:**
```
http://192.168.254.44:8081/api/proxy/grafana/d/a2lcqz/sagesmp-devices
http://192.168.254.44:8081/api/proxy/grafana/d/a2lcqz/sagesmp-pihole
```

### Alerting & Email Notifications

**Prometheus Alerts**: Configured with Alertmanager on Pi4 running on port 9093. Notifications are routed to `quegmeister@gmail.com` for both warning and critical levels.

**Alert Types**:
- CPU temperature warnings (70°C-85°C), critical (>85°C)
- Memory pressure alerts (low to critical memory levels)
- Service status (Pi-hole, Grafana, Prometheus, Alertmanager, Loki)
- Compile failure detection
- Device connection monitoring
- External endpoint checks (Blackbox exporter)

**Email Notification Setup**:
```
# To use email alerts, create a Gmail App Password at:
# https://myaccount.google.com/apppasswords

# Update the Alertmanager configuration:
global:
  smtp_auth_password: \"YOUR_GMAIL_APP_PASSWORD\"
  smtp_from: sagesmp@orangepi.local
  smtp_auth_username: quegmeister@gmail.com

# To receive email alerts from: quegmeister@gmail.com
# Set up SMTP for Gmail
```

Alerts are grouped by severity and sent at the following intervals:
- **Critical alerts**: 30-minute repeat interval
- **Warning alerts**: 6-hour repeat interval

Alertmanager manages inhibition rules to prevent duplicate alerts (critical alerts suppress duplicates of related warning alerts).

### Grafana Loki

**Centralized Log Management**

Grafana can also consolidate system logs from all cluster nodes via **Loki** (log aggregation). For advanced log analysis, you can run the log shipper setup script to configure remote log forwarding:

```bash
# On an OrangePi or Pi2 device, set up log forwarding:
bash /tmp/setup_logshipper.sh
```

From Grafana, you can query and visualize logs across multiple nodes, enabling centralized debugging and monitoring of system events.

### External Endpoint Monitoring

**Blackbox Exporter**

The stack includes a **Blackbox exporter** for active checks of external endpoints, ensuring observability into:

- **Internal services**: Dashboard (`http://192.168.254.44:8081`), Prometheus (`http://10.42.0.141:9090`), Grafana (`http://10.42.0.141:3000`)
- **Remote devices**: Pi2 SSH port (`http://10.42.1.109`)
- **Internet services**: Google (`https://google.com`), GitHub (`https://github.com`)

Blackbox exporter runs on port 9115 on Pi4 and uses standard HTTP (2xx, 301-302, 307) and ICMP checks.

### Persistent Grafana Configuration

All Grafana dashboards are provisioned via configuration files under `conf/grafana/provisioning/dashboards/`:

**Provider configuration** (`sagesmp_provider.yml`):
```yaml
providers:
  - name: SageSMP
    orgId: 1
    folder: SageSMP
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/provisioning/dashboards/sagesmp
```

This means dashboards persist across Grafana restarts and are automatically reloaded when updated.

### Resource Usage History & Annotations

The dashboard automatically records service status changes, component start/stop events, and every heartbeat into an **events system**. Grafana supports adding these events as **annotations** to dashboards, showing timeline markers for:

- Node service state changes
- Cross-compile completions (with platform, duration, exit code)
- Client connections/disconnections
- Error and warning events

Annotations appear as colored horizontal bands on the time-based Grafana graphs, providing instant operational context.

### Additional SageSMP Metrics

The **`/api/metrics` endpoint** now also exposes enhanced telemetry:

**New metrics added:**
- `sagesmp_relay_uptime_seconds`: Seconds since OrangePi relay started
- `sagesmp_compile_count`: Total number of cross-compile runs
- `sagesmp_seconds_since_last_compile`: Time since last successful build
- `sagesmp_relay_running`: 1 if relay process is running
- Service metrics for `alertmanager`, `grafana`, `loki`, `prometheus`, and `promtail` (all 1 if active)

This expanded Prometheus metric collection provides complete visibility into build pipeline status, relay health, and the entire monitoring stack.

### Prometheus Configuration

Prometheus runs on **Pi4 (10.42.0.141:9090)** and is configured to scrape:

1. **SageSMP metrics**: `http://192.168.254.44:8081/api/metrics` (via `sagesmp` job)
2. **Node exporters**: Pi4 (localhost:9100), Pi2 (10.42.1.109:9100), OrangePi (10.42.0.1:9100)
3. **Prometheus itself**: localhost:9090

Configuration file: `/etc/prometheus/prometheus.yml` on Pi4.

### Node Exporters

- **Pi4 (arm64)**: `prometheus-node-exporter` package, port 9100 — already installed.
- **Pi2 (armhf)**: `prometheus-node-exporter` package, port 9100 — installed.
- **OrangePi (riscv64)**: `prometheus-node-exporter` package, port 9100 — installed from Ubuntu RISC-V repos.

### Grafana Dashboards

Grafana runs on **Pi4 (10.42.0.141:3000)** and is pre-configured with:

- **Prometheus data source**: Added via provisioning at `/etc/grafana/provisioning/datasources/prometheus.yaml`.
- **SageSMP Cluster dashboard**: Pre-built dashboard (`/d/a2lcqz/sagesmp-cluster`) with panels for:
  - CPU temperature, load, and frequency per device
  - Memory available and total per device
  - Pi-hole and Grafana/Prometheus service status
  - Node exporter system metrics (CPU, memory, disk, network)
- **Anonymous access**: Enabled (Viewer role) for embedded dashboard access through the dashboard proxy.
- **Admin credentials**: `admin` / `admin` (default).

### Accessing Grafana Dashboards

From the dashboard hamburger menu, the **Grafana** item embeds the Grafana login page via the proxy. After logging in (`admin`/`admin`), you can navigate to the **SageSMP Cluster** dashboard under the Dashboards menu, or access it directly at:

```
http://192.168.254.44:8081/api/proxy/grafana/d/a2lcqz/sagesmp-cluster
```


