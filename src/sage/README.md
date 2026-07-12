# SageSMP - Pure Sage Multicore Protocol

A modular, mailbox-based protocol for multicore message passing implemented in pure SageLang.

## Overview

SageSMP provides a distributed messaging system inspired by Erlang-style mailboxes, designed for multi-node communication. It handles node discovery, message routing, and reliable delivery across a network of Sage nodes.

## Real Multi-Node Networking

The implementation has been fully migrated from simulated mocks to real network communication:
- **Native TCP Sockets**: The transport layer is fully wired to native OS sockets via Sage's `tcp` module, allowing separate nodes on different machines or processes to communicate over real TCP/IP connections.
- **JSON Protocol Encoding**: Message serialization/deserialization uses custom pure-Sage JSON codec (Sage's `import json` causes a compiler ICE when compiling to ELF).
- **60-Second Heartbeat**: Each client connects to the OrangePi relay every 60 seconds, sending system telemetry and receiving cluster status.

## Important: Sage Compiler Limitations

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

**Always use `sage --jit`** for real TCP networking:

```bash
# On OrangePi
stdbuf -oL sage --jit src/sage/server/orangepi_relay.sage

# Or with custom port
SMP_PORT=42001 stdbuf -oL sage --jit src/sage/server/orangepi_relay.sage
```

### Running the Clients

```bash
# On RPi2/PeachPi
SMP_HOST="192.168.254.44" stdbuf -oL sage --jit src/sage/client/rpi2_client.sage

# On RPi4
SMP_HOST="192.168.254.44" stdbuf -oL sage --jit src/sage/client/rpi4_client.sage
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

The `sagemake` build script compiles all three targets:

```bash
./sagemake --all
```

For quick deployment to devices:

```bash
# Copy to OrangePi
rsync -av src/sage/server/orangepi_relay.sage src/sage/client/ OrangePi:~/SageSMP/src/sage/

# Then from OrangePi to pi2/pi4
ssh OrangePi "cat ~/SageSMP/src/sage/client/rpi2_client.sage | ssh evelyn@10.42.1.109 'cat > ~/SageSMP/src/sage/client/rpi2_client.sage'"
ssh OrangePi "cat ~/SageSMP/src/sage/client/rpi4_client.sage | ssh ubuntu@10.42.0.141 'cat > ~/SageSMP/src/sage/client/rpi4_client.sage'"
```

### Dashboard

A FastAPI dashboard on OrangePi port 8081 monitors the cluster:

```bash
cd dashboard
python3 app.py
# Open http://192.168.254.44:8081
```

The dashboard captures process output from the relay and clients via SSE.

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

## License

MIT
