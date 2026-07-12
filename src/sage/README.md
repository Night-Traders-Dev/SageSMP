# SageSMP - Pure Sage Multicore Protocol

A modular, mailbox-based protocol for multicore message passing implemented in pure SageLang.

## Overview

SageSMP provides a distributed messaging system inspired by Erlang-style mailboxes, designed for multi-node communication. It handles node discovery, message routing, and reliable delivery across a network of Sage nodes.

## Real Multi-Node Networking

The implementation has been fully migrated from simulated mocks to real network communication:
- **Native TCP Sockets**: The transport layer (`smp.transport`) is fully wired to native OS sockets via Sage's `tcp` module, allowing separate nodes on different machines or processes to communicate over real TCP/IP connections.
- **JSON Protocol Encoding**: Message serialization/deserialization uses Sage's standard `json` port, assuring full payload compatibility and correct routing of dynamic types.
- **Base64-safe Cryptography**: The XOR cipher has been updated to use Base64 encoding to prevent null-byte (`chr(0)`) truncation and UTF-8 code point corruption when transmitting encrypted envelopes over socket buffers.

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
│   └── client_shell.sage  # Interactive client shell with OTP encryption
├── server/
│   ├── server.sage        # Server implementation for accepting connections
│   └── relay.sage         # Configurable relay server with OTP encryption
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

# Connect to server
client.connect("127.0.0.1", 42000)

# Register message handler
client.on("1", proc(msg):
    print "Received: " + str(msg["payload"])
)

# Send a message to another node
let seq = client.send(2, {"data": "Hello, node 2!"})

# Run event loop
client.run()
```

### Creating a Server

```sage
import smp.server

let server = smp_server.Server("cluster-master", "0.0.0.0", 42000)

# Register event handlers
server.on("message", proc(sender, target, payload):
    print "Message from " + str(sender) + " to " + str(target)
)

# Start accepting connections
server.start()
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

## Mailbox System

The mailbox system provides FIFO message queues with optional capacity limits:

```sage
import smp.mailbox

# Create mailbox with 100 message capacity
let mbox = smp_mailbox.create_mailbox(node_id, 100)

# Send messages
let msg = smp_mailbox.create_message(sender, recipient, MSG_TYPE_DATA, payload)
let seq = smp_mailbox.send(mbox, msg)

# Receive messages
let received = smp_mailbox.recv(mbox)

# Register handlers for automatic processing
smp_mailbox.on_mail(mbox, MSG_TYPE_DATA, proc(msg):
    # Handle message
)
```

## Node States

- `NODE_STATE_DISCONNECTED` (0) - Node not connected
- `NODE_STATE_CONNECTING` (1) - Connection in progress
- `NODE_STATE_CONNECTED` (2) - TCP connected
- `NODE_STATE_READY` (3) - Ready for messaging
- `NODE_STATE_ERROR` (4) - Error state

## Running Tests

```bash
sage src/sage/demo/example.sage
```

Or compile to binary:
```bash
sage --compile src/sage/demo/demo.sage -o bin/demo_smp
./bin/demo_smp
```

### Demo Output

The demo shows:
- **Mailbox**: Message queuing with FIFO delivery and statistics tracking
- **Node Registry**: Node discovery, registration, and capability management  
- **RTOS**: Priority-based task scheduling with periodic GC-aware memory cleanup

Example:
```
=== SageSMP Mailbox Demo ===
Sending messages...
  Sent 5 messages
Processing messages...
  Handler: Received message #1: Message 1
  ...
Mailbox stats:
  Sent: 5
  Received: 5
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

## Building

Use the included sagemake script:

```bash
# Initialize config file
./sagemake --init-config

# Build all binaries
./sagemake --all

# Build specific component
./sagemake src/sage/client/client_shell

# Build relay server
./sagemake --relay

# Build client shell
./sagemake --client

# Run demo
./bin/demo_smp

# Run tests
./sagemake --test
```

## Architecture

```
┌─────────────────────────────────────────────┐
│              Application Layer               │
├─────────────────────────────────────────────┤
│         Client/Server (smp.client)          │
├─────────────────────────────────────────────┤
│          Transport (smp.transport)          │
├─────────────────────────────────────────────┤
│           Protocol (smp.core)             │
├─────────────────────────────────────────────┤
│           Mailbox (smp.mailbox)            │
├─────────────────────────────────────────────┤
│             Crypto (smp.crypto)             │
└─────────────────────────────────────────────┘
```

## License

MIT

## SageSMP Cluster (OrangePi + RPi2 + RPi4)

### OrangePi Relay Server

The OrangePi acts as the central relay server for the cluster:

```bash
# On OrangePi
./sagemake --orangepi
./bin/orangepi_relay
```

The relay listens on `0.0.0.0:42000` and collects periodic info from connected clients.

### RPi2/RPi4 Clients

Clients connect to the OrangePi relay and share periodic system status:

```bash
# On RPi2 (10.42.1.109)
./sagemake --rpi2
./bin/rpi2_client
# Sends: Temp, Load, Memory info every 5 ticks

# On RPi4 (10.42.0.141)
./sagemake --rpi4
./bin/rpi4_client
# Sends: Temp, Load, Memory, GPU temp, Throttling status
```

### Dashboard Integration

The SageCluster dashboard includes SMP protocol monitoring:

- **API Endpoint**: `/api/smp-status` - Returns running status of relay and clients
- **JS Module**: `static/js/smp_monitor.js` - Updates dashboard with SMP cards in real-time

To deploy on OrangePi:
```bash
# Copy source
rsync -av src/sage OrangePi:~/SageSMP/
scp sagemake OrangePi:~/SageSMP/

# Build on OrangePi
ssh OrangePi '~/SageSMP/sagemake --orangepi'

# Restart dashboard to see SMP cards
ssh OrangePi 'pm2 restart sagecluster'
```

### Network Configuration

```
OrangePi (192.168.1.10) - Relay Server - port 42000
├── RPi2 (10.42.1.109) - Client - port 42001
└── RPi4 (10.42.0.141) - Client - port 42002
```

Shared secret for OTP encryption: `orangepi_cluster_secret_2026`

## Build Configuration

Create `.smp_config` to customize build settings:

The relay server allows runtime configuration of message forwarding rules with OTP encryption:

```sage
# Add relay rule: when trigger_msg received, forward forward_msg to target
# All forwarded messages are automatically OTP-encrypted
add_relay_rule("hello", "192.168.1.100", 42001, "Hello from relay!", "secret_key", "otp_pass", 100)
add_relay_rule("status", "192.168.1.100", 42001, "Status OK", "secret_key", "otp_pass", 200)

# Shell commands for runtime configuration
relay_shell_help()
#   add <trigger> <host> <port> <forward_msg>  - Add relay rule
#   remove <index>                           - Remove relay rule
#   list                                     - List all rules
#   clear                                    - Clear all rules
```

## Client Shell

Interactive shell for connecting to and messaging any node with OTP encryption:

```sage
client_connect("192.168.1.100", 42001)
client_send_secure("192.168.1.100", 42001, "My message", "secret_key", "otp_pass", 999, sender_id, recipient_id)
client_show_outbox()
```

## End-to-End Encryption

All secure messaging uses pure Sage OTP encryption:

```sage
# Send encrypted message
let envelope = secure_send(message, secret_key, otp_passphrase, otp_seed, sender_id, recipient_id)

# Receive and decrypt
let decrypted = secure_receive(envelope, secret_key, otp_passphrase, otp_seed, expected_sender)
```

The encryption uses:
- **OTP Key**: Derived from passphrase + seed using pure Sage hash
- **Signing**: Simple hash-based signature with secret key
- **No external dependencies**: Pure Sage implementation

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