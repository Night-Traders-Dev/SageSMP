# SageSMP - Pure Sage Multicore Protocol

A modular, mailbox-based protocol for multicore message passing implemented in pure SageLang.

## Overview

SageSMP provides a distributed messaging system inspired by Erlang-style mailboxes, designed for multi-node communication. It handles node discovery, message routing, and reliable delivery across a network of Sage nodes.

## Real Multi-Node Networking

The implementation has been fully migrated from simulated mocks to real network communication:
- **Native TCP Sockets**: The transport layer is fully wired to native OS sockets via Sage's `tcp` module, allowing separate nodes on different machines or processes to communicate over real TCP/IP connections.
- **JSON Protocol Encoding**: Message serialization/deserialization uses custom pure-Sage JSON codec (Sage's `import json` causes a compiler ICE when compiling to ELF).
- **60-Second Heartbeat**: Each client connects to the OrangePi relay every 60 seconds, sending system telemetry and receiving cluster status.

## Important: Sage Compiler Limitations & Version Requirements

- **Requires SageLang v4.0.8+** to properly compile using AOT due to string, array, and global scope fixes introduced in v4.0.6, and multi-architecture JIT support added in v4.0.8.
- **Do not use `import json`** — it causes an internal compiler error when compiling to ELF with `sage --compile`. A pure-Sage JSON encoder/decoder is used instead.
- **Compiled ELF binaries (`sage --compile`) have a runtime bug with `tcp.listen()`** that returns `nil` or crashes. Always run with `sage --jit` for real TCP networking.
- **Semicolons are not allowed** — each statement must be on its own line.
- **`io.readfile()` includes trailing newlines** — use `stripnl()` before `tonumber()`.
- **`thread.spawn(func)` with zero args causes ICE** — use `thread.spawn(func, nil)` with a dummy parameter.
- **Avoid `chr()` inside for-loops combined with array indexing** — a Sage compiler bug corrupts scope tracking. Use simple string concatenation with precomputed values instead.

## Module Structure

```
src/sage/
├── core/
│   ├── __init__.sage      # Core definitions, constants, version
│   └── smp_protocol.sage  # Protocol message types and encoding
├── mailbox/
│   └── mailbox.sage       # Mailbox system for message queuing and delivery
├── crypto/
│   ├── crypto.sage        # Message signing and encryption utilities
│   ├── secure_msg.sage    # Secure message API with OTP encryption
│   └── otp_crypto.sage    # Standalone OTP encryption demo
├── node/
│   └── node.sage          # Node identity, registry, and lifecycle management
├── transport/
│   └── transport.sage     # Network transport layer (TCP framing)
├── client/
│   ├── client.sage        # Client implementation for connecting to servers
│   ├── client_shell.sage  # Interactive client shell
│   ├── rpi2_client.sage   # RPi2 heartbeat client with CPU telemetry
│   └── rpi4_client.sage   # RPi4 heartbeat client with GPU telemetry
├── server/
│   ├── server.sage        # Server implementation for accepting connections
│   ├── relay.sage         # Configurable relay server
│   └── orangepi_relay.sage # OrangePi central relay (port 42000)
├── rtos/
│   └── rtos.sage          # Pure-Sage RTOS scheduler with GC-aware cleanup
└── demo/
    ├── demo.sage          # Runnable demo (compiles to ELF binary)
    └── example.sage       # Usage examples and test suite
```

## Quick Start

### Creating a Client

```sage
import smp.client

let client = smp_client.Client("my-node", "127.0.0.1", 42000)
client.connect("127.0.0.1", 42000)
client.on("1", proc(msg):
    print "Received: " + str(msg["payload"])
)
let seq = client.send(2, {"data": "Hello, node 2!"})
client.run()
```

### Creating a Server

```sage
import smp.server

let server = smp_server.Server("cluster-master", "0.0.0.0", 42000)
server.on("message", proc(sender, target, payload):
    print "Message from " + str(sender) + " to " + str(target)
)
server.start()
```

## SageSMP Cluster (OrangePi + RPi2 + RPi4)

### Architecture

```
OrangePi (192.168.254.44) - Relay Server (port 42000) + Dashboard (port 8081)
├── RPi2/PeachPi (10.42.1.109) - Client - sends CPU temp/load/memory
└── RPi4/ubuntu (10.42.0.141)  - Client - sends CPU/GPU temp, load, memory, throttling
```

Each client connects to the OrangePi relay every 60 seconds via TCP, sends a JSON heartbeat with system telemetry, and receives a response with cluster node count and server timestamp.

### Running the Relay

```bash
# On OrangePi (Default port 42000)
./bin/sagesmp relay

# Or with custom port
./bin/sagesmp relay 42001
```

### Running the Clients

The client telemetry scripts can connect to any IP/Port dynamically:

```bash
# On RPi2/PeachPi
./bin/sagesmp pi2 <Relay IP> <Relay Port>

# On RPi4
./bin/sagesmp pi4 <Relay IP> <Relay Port>
```

### Running the Universal Interactive Shell

The universal client shell allows you to join the cluster interactively from any machine:

```bash
# Connect as a client
./bin/sagesmp shell --host 192.168.254.44 --port 42000

# Spin up a local mock router
./bin/sagesmp shell --router --host 127.0.0.1 --port 42000
```

The clients will:
1. Connect to the relay and send a JSON heartbeat
2. Print `[HEARTBEAT OK]` with node count and server timestamp
3. Sleep for 60 seconds, then repeat

### Protocol

The relay sends a plain JSON response (no OTP encryption):

```json
// Client -> Relay
{"client_id": 1, "platform": "RPi2", "info": "Temp: 36.8C, Load: 0.4, Available: 768MB", "timestamp": 1234567890}

// Relay -> Client
{"status": "ok", "node_count": 2, "server_ts": 1234567890}
```

### Deploying Updates

The `sagemake` build script compiles all targets and creates a unified single binary launcher:

```bash
./sagemake --sagesmp
```

For quick deployment to devices, you can simply transfer the `bin/sagesmp` script and the unified `src/sage/sagesmp.sage` file:

```bash
# Copy to OrangePi
rsync -av bin/sagesmp src/sage/sagesmp.sage OrangePi:~/SageSMP/bin/

# Execute on remote instances as needed
ssh OrangePi "./bin/sagesmp relay 42000"
```

### Dashboard

A FastAPI dashboard on OrangePi port 8081 monitors the cluster:

```bash
cd dashboard
python3 app.py
# Open http://192.168.254.44:8081
```

The dashboard captures process output from the relay and clients via SSE.

### Pi-hole Ad-Blocking & Protocol Logging

Pi-hole runs on **Pi2/PeachPi** (10.42.1.109) and provides DNS-level ad blocking, query logging, and full packet capture for all cluster devices.

#### DNS Routing

| Device | DNS Server | Route | Notes |
|--------|-----------|-------|-------|
| Pi2 | `127.0.0.1:53` | Local | Uses its own Pi-hole instance |
| OrangePi | `10.42.1.109:53` | Direct | Reaches Pi2 via end0 interface |
| Pi4 | `10.42.0.1:53` | Via OrangePi | OrangePi NM dnsmasq on end1 forwards to Pi2 |

#### Ad-Blocking

- `pihole enable` — blocks ads at the DNS level
- `pihole updateGravity` — updates blocklists
- Privacy level: **0** (log all domains, no anonymization)

#### Query Logging

- `pihole logging on` — all DNS queries logged to `/var/log/pihole/pihole.log`
- FTL config: `QUERY_LOGGING=true`, `MAXLOGAGE=365`, `VERBOSE=true`

#### Packet Capture (tcpdump)

A systemd service `pihole-capture` runs tcpdump on all interfaces, capturing all protocols (TCP, UDP, DNS, HTTP, HTTPS, ICMP, etc.) except SSH. Files rotate daily with 7-day retention via logrotate.

**Service:** `/etc/systemd/system/pihole-capture.service`

```
/usr/bin/tcpdump -i any -G 86400 -w /var/log/pihole_traffic/capture_%Y%m%d.pcap -z /usr/bin/gzip -C 5000 not port 22
```

Output: compressed `.pcap.gz` files in `/var/log/pihole_traffic/` (rotated after 7 days).

#### Monitoring Script

`scripts/sagesmp-pihole.sh` runs via cron every 5 minutes on Pi2, capturing Pi-hole telemetry:

```json
{"pihole_active":"active","blocking":"enabled","logging":"enabled",
 "privacy_level":0,"queries_today":1234,"listening":1,"ftl_pid":1255,
 "pcap_active":"active"}
```

#### Dashboard Live Console

The dashboard streams four Pi-hole logging feeds to the live console:

1. **`[Pi-hole]`** — Real-time DNS queries from `/var/log/pihole/pihole.log`
2. **`[DNS]`** — Pi-hole syslog entries from iptables
3. **`[TCP]` `[UDP]` `[DNS]` `[HTTP]` `[HTTPS]` `[ICMP]`** — Live tcpdump packet summaries with protocol classification tags
4. **Services panel** — Pi-hole blocking/logging/pcap status from heartbeat telemetry

### Grafana/Prometheus & Cross-Compile (Pi4)

Each client enriches its 60-second heartbeat with extra service telemetry. The relay prints
`[SERVICES]` and `[COMPILE]` lines, which the dashboard parses into a rolling JSON-lines log
(`~/SageSMP/logs/service_log.jsonl`) and exposes via `/api/service-log`, `/api/compiles`, and
`/api/status`.

**Data flow:**

```
Pi2  /usr/local/bin/sagesmp-pihole.sh      -> /tmp/sagesmp_pihole.json
Pi4  /usr/local/bin/sagesmp-services.sh    -> /tmp/sagesmp_services.json
Pi4  /usr/local/bin/sagesmp-crosscompile.sh -> /tmp/sagesmp_compile_result.json

Shell scripts (cron) -> JSON files on device
  -> Sage client reads file each heartbeat (io.readfile + pure-Sage json_decode)
  -> heartbeat JSON gains "services" / "compile" fields
  -> relay prints [SERVICES]/[COMPILE]
  -> dashboard parses + stores + renders in UI
```

**Heartbeat protocol extensions:**

```json
// RPi2 -> Relay  (Pi-hole status)
{"client_id": 1, "platform": "RPi2", "info": "...", "timestamp": 123,
 "services": {"pihole_active":"active","blocking":"enabled","logging":"enabled",
              "privacy_level":0,"queries_today":1234,"listening":1,"ftl_pid":1255,"pcap_active":"active"}}

// RPi4 -> Relay  (Grafana + Prometheus)
{"client_id": 2, "platform": "RPi4", "info": "...", "timestamp": 123,
 "services": {"grafana": "active", "grafana_version": "11.5.2", "prometheus": "active", "prometheus_main": "active", "uptime": "..."},
 "compile": {"status": "ok", "exit_code": 0, "start": "...", "end": "...", "duration": 13, "output": "..."}}
```

**Helper scripts** (in `scripts/`):

| Script | Host | Output | Purpose |
|--------|------|--------|---------|
| `sagesmp-pihole.sh` | Pi2 | `/tmp/sagesmp_pihole.json` | Pi-hole FTL status, blocking, logging, pcap state |
| `sagesmp-services.sh` | Pi4 | `/tmp/sagesmp_services.json` | Grafana server health + Prometheus node-exporter status |
| `sagesmp-crosscompile.sh` | Pi4 | `/tmp/sagesmp_compile_result.json` | Runs `./sagemake --all`, captures exit code, timestamps, duration, output |
| `setup-pi4-dns.sh` | Host | N/A | Configure Pi4 DNS via OrangePi relay (run when Pi4 is online) |

**Cron setup** (install via `crontab -e` on each device):

```bash
# On Pi2 (every 5 minutes)
*/5 * * * * /usr/local/bin/sagesmp-pihole.sh

# On Pi4 (every 5 minutes + daily cross-compile at 3 AM)
*/5 * * * * /usr/local/bin/sagesmp-services.sh
0 3 * * * /usr/local/bin/sagesmp-crosscompile.sh
```

**Dashboard panels:**

- **Service Status** — live Pi-hole (RPi2) and Grafana/Prometheus (RPi4) state from the SSE `services` feed.
- **Protocol Logs** — live packet capture with protocol tags in the console output.
- **Cross-Compile History** — latest compile runs (status, exit code, duration) from `/api/compiles`.
- **Service Log** — rolling log of every `[SERVICES]`/`[COMPILE]` event from `/api/service-log`.

> Note: the cross-compile `output` field contains newlines escaped as `\n`; the Sage JSON codec
> preserves them through the decode/encode round-trip so they render correctly in the dashboard.

### Prometheus & Grafana Monitoring

The dashboard exposes SageSMP heartbeat telemetry as native Prometheus metrics via `/api/metrics` on the OrangePi, enabling Prometheus (running on Pi4 at `10.42.0.141:9090`) to scrape cluster data directly.

**Metrics endpoint**: `http://192.168.254.44:8081/api/metrics` exposes:
- `sagesmp_cpu_temp_celsius{device="..."}` — CPU temperature per device
- `sagesmp_cpu_load{device="..."}` — CPU load average
- `sagesmp_memory_available_bytes{device="..."}` — available memory per device
- `sagesmp_cpu_freq_hz{device="..."}` — current CPU frequency
- `sagesmp_connected_clients` — clients connected to relay
- `sagesmp_up{device="..."}` — device connectivity (1=connected)
- `sagesmp_pihole_active/blocking`, `sagesmp_grafana_active`, `sagesmp_prometheus_active` — service status

**Node exporters** (port 9100) run on all three devices:
- OrangePi (riscv64): installed from Ubuntu repos
- Pi2 (armhf): `prometheus-node-exporter` package
- Pi4 (arm64): `prometheus-node-exporter` package

**Grafana** (Pi4 at `10.42.0.141:3000`) has:
- Prometheus data source provisioned at `/etc/grafana/provisioning/datasources/prometheus.yaml`
- Pre-built **SageSMP Cluster** dashboard (`/d/a2lcqz/sagesmp-cluster`) with CPU, memory, service status, and node_exporter system panels
- Anonymous read-only access enabled for embedded use through the dashboard proxy

## Mailbox System

The mailbox system provides FIFO message queues with optional capacity limits:

```sage
import smp.mailbox

let mbox = smp_mailbox.create_mailbox(node_id, 100)
let msg = smp_mailbox.create_message(sender, recipient, MSG_TYPE_DATA, payload)
let seq = smp_mailbox.send(mbox, msg)
let received = smp_mailbox.recv(mbox)
smp_mailbox.on_mail(mbox, MSG_TYPE_DATA, proc(msg):
    # Handle message
)
```

## Protocol Opcodes

| Opcode | Name | Description |
|--------|------|-------------|
| 0 | HEARTBEAT | Keep-alive ping |
| 1 | MESSAGE | Data message between nodes |
| 2 | JOIN | Node join notification |
| 3 | LEAVE | Node leave notification |
| 4 | MAILBOX | Direct mailbox transfer |
| 5 | MAILBOX_ACK | Mailbox operation acknowledgment |
| 6 | SYNC | State synchronization |
| 7 | SYNC_ACK | Sync acknowledgment |
| 8 | BROADCAST | Broadcast to all nodes |
| 9 | NODE_INFO | Node metadata exchange |

## Running Tests

```bash
sage src/sage/demo/example.sage
```

Or compile to binary:
```bash
sage --compile src/sage/demo/demo.sage -o bin/demo_smp
./bin/demo_smp
```

## Configuration

Environment variables:
- `SMP_HOST` - Default host (default: 127.0.0.1)
- `SMP_PORT` - Default port (default: 42000)

Defaults can be overridden in code:
- `DEFAULT_HOST`
- `DEFAULT_PORT`
- `DEFAULT_TIMEOUT_MS` (5000)
- `DEFAULT_MAX_NODES` (64)
- `DEFAULT_MAILBOX_SIZE` (1024)

## Build Configuration

Create `.smp_config` to customize build settings:

```json
{
  "host": "127.0.0.1",
  "port": 42000,
  "relay_host": "0.0.0.0",
  "relay_port": 42000,
  "enable_rtos": true,
  "enable_crypto": true
}
```

## Dashboard & Cluster Control Center

A modern, glassmorphic real-time dashboard is available to monitor and manage the SageSMP cluster (OrangePi relay + RPi2 + RPi4 clients).

### Running the Dashboard

1. **Install Python dependencies** (inside a virtual environment):
   ```bash
   cd dashboard
   python3 -m venv venv
   source venv/bin/activate
   pip install fastapi uvicorn jinja2
   ```
2. **Start the server**:
   ```bash
   python3 app.py
   ```
3. Open `http://<orangepi-ip>:8081` in your browser.

### Key Features

* **Real-Time SSE Telemetry**: Process status, PIDs, active logs, client CPU/GPU temperatures, memory load, and telemetry updates are pushed instantly via Server-Sent Events (SSE). No background polling is required.
* **Formatted Live Console & Events**: Process logs and cluster events are dynamically formatted with distinct emojis and tag highlights in the UI (e.g. 🟢 `HEARTBEAT`, ✅ `HEARTBEAT OK`, ⚙️ `SERVICES`, 🛠️ `COMPILE`).
* **Overlay Terminal Console**: Access an interactive command console by clicking the terminal icon in the header.
* **Interactive Expandable Components**: Click on any node performance card, active service item, or cross-compile run card to expand it and reveal granular system metrics, config files, and build logs.

### Terminal Commands

#### General Commands
* `help` - Show available console tools.
* `status` - Tabulate status (Running, Stopped, PID, Log Count) of all cluster nodes.
* `info <device>` - Execute system telemetry queries (`uptime`, `free -h`, `df -h /`, `uname -a`) on OrangePi, pi2, or pi4.
* `start <device>` / `stop <device>` - Spin up or shut down specific nodes or all nodes (`all`).
* `clear` - Clear console output.
* `sc <device>` (Sage Connect) - Connect directly to the terminal shell of a device (local or SSH) with a fully interactive shell:
  * `sc OrangePi` - Local OrangePi `/bin/bash` shell.
  * `sc pi2` - Remote `ssh pi2` shell.
  * `sc pi4` - Remote `ssh pi4` shell.
  * Type `exit` to return to the `sage> ` prompt.
* `smp-mailboxes` - List active SageSMP mailboxes, pending message counts, and delivery metrics.
* `smp-read <device>` - Fetch and display all queued messages inside the target device's mailbox.
* `smp-send <src_device> <dst_device> <message>` - Compose and dispatch a message from a source device to a destination device's mailbox across SageSMP.

#### Service Management Commands

* `pihole <args>` - Run Pi-hole commands on the Pi2 node. Examples:
  * `pihole status` - Show blocking status.
  * `pihole enable` / `pihole disable` - Toggle ad-blocking.
  * `pihole -g` - Update gravity (ad lists).
  * `pihole restartdns` - Restart DNS resolver.
  * `pihole logging on` / `pihole logging off` - Toggle DNS query logging.

* `grafana <args>` - Manage Grafana on Pi4. Examples:
  * `grafana status` - Show service status.
  * `grafana restart` / `grafana start` / `grafana stop` - Control the service.
  * `grafana logs` - Show the last 50 log lines.

* `prometheus <args>` - Manage Prometheus on Pi4. Examples:
  * `prometheus status` - Show service status.
  * `prometheus restart` / `prometheus start` / `prometheus stop` - Control the service.
  * `prometheus logs` - Show the last 50 log lines.

#### Cluster-Wide Apt

* `apt <args>` - Run `sudo apt <args>` on **all three devices simultaneously** (OrangePi, Pi2, Pi4). Output is labelled per-device and aggregated. Examples:
  * `apt update` - Refresh package lists across the cluster.
  * `apt upgrade` - Upgrade packages on all devices.
  * `apt update && apt dist-upgrade` - Full system update.
  * `apt install <package>` - Install a package cluster-wide.

#### Setup

* `setup-sudo` - Configure passwordless sudo on all three devices (required for `apt`, service management, and Pi-hole commands). Creates `/etc/sudoers.d/sagesmp` on each device. Optionally accepts a custom password: `setup-sudo <password>`. A standalone script is also available at `scripts/setup-sudo.sh`.

## Performance Benchmarks (SageLang v4.0.8)

Micro-benchmarks run on the SageSMP stack using the AST Interpreter and JIT backends (x86-64). The JIT backend uses native tail-call trampolines with profiling-guided compilation for hot functions.

| Module / Operation | AST Interpreter (ops/sec) | JIT (ops/sec) |
|--------------------|--------------------------|---------------|
| **Mailbox (Send + Recv)** | 743 | 731 |
| **Protocol Encode** | 33,753 | 34,532 |
| **Protocol Decode** | 6,045 | 6,225 |
| **Crypto (Encrypt + Decrypt)** | 2,531 | 2,583 |
| **Transport Buffer Writes** | 6,354 | 6,333 |

*Run with: `sage -I src src/sage/demo/benchmark.sage` (AST) or `sage -I src --jit src/sage/demo/benchmark.sage` (JIT). GC disabled during benchmarks. Benchmarks cover 10K-20K iterations per operation.*

## License

MIT

## SSH ProxyJump Configuration

To connect directly to the Pi2 and Pi4 from your host machine (bypassing the need to SSH into OrangePi first), add the following to your host's `~/.ssh/config` file:

```ssh-config
Host OrangePi
    HostName 192.168.254.44
    User kraken

Host pi2
    HostName 10.42.1.109
    User pi
    ProxyJump OrangePi

Host pi4
    HostName 10.42.0.141
    User ubuntu
    ProxyJump OrangePi
```

This allows you to simply run `ssh pi2` or `ssh pi4` directly from your host.

## AOT and Cross-Compilation

SageLang's AOT (Ahead-of-Time) compiler and JIT-guided AOT workflows are fully supported. SageSMP provides a single unified binary (`sagesmp.sage`) containing all components (Relay, Pi2 client, Pi4 client, Shell). 

You can cross-compile the SageSMP unified binary for multiple architectures using the AOT compiler and cross-platform GCC:

```bash
# 1. Generate C code from SageSMP via AOT
sage --aot src/sage/sagesmp.sage > sagesmp.c

# 2. Compile for target architectures
# x86_64
gcc -std=c11 -O2 sagesmp.c -o sagesmp-x86_64 -lm

# ARM64 (Raspberry Pi 4, etc.)
aarch64-linux-gnu-gcc -std=c11 -O2 sagesmp.c -o sagesmp-aarch64 -lm

# RISC-V 64 (OrangePi, etc.)
riscv64-linux-gnu-gcc -std=c11 -O2 sagesmp.c -o sagesmp-rv64 -lm
```

You can also use Profile-Guided AOT Compilation using the JIT:
```bash
sage --aot --jit src/sage/sagesmp.sage -o sagesmp_optimized
```
