# Client Module

Client implementation for SMP protocol with mailbox integration.

## Overview

The client module provides the `Client` class for connecting to SMP servers and the factory functions for creating clients.

## API Reference

### Client Class

```sage
class Client
```

#### Methods

```sage
proc init(self, name, host, port)
```
Initialize client with name and bind address. Creates local node and mailbox.

```sage
proc connect(self, target_host, target_port) -> bool
```
Connect to target server, send JOIN message.

```sage
proc disconnect(self) -> bool
```
Send LEAVE message, close connection.

```sage
proc send(self, target_id, payload) -> seq
```
Send data message to target node.

```sage
proc broadcast(self, payload) -> bool
```
Broadcast message to all nodes.

```sage
proc on(self, msg_type, handler)
```
Register message handler for message type or `*` for all.

```sage
proc poll(self) -> raw_msg_or_nil
```
Poll connection for incoming messages.

```sage
proc process_mailbox(self)
```
Process all pending mailbox messages.

```sage
proc tick(self)
```
Single tick: poll, process mailbox, send heartbeat if needed.

```sage
proc run(self)
```
Run main event loop until stopped.

```sage
proc stop(self)
```
Stop event loop and disconnect.

```sage
proc get_stats(self) -> stats_dict
```
Get client statistics: node_id, node_name, state, transport, mailbox.

### Factory Functions

```sage
proc create_client(name, host, port) -> Client
```
Create client with explicit host/port.

```sage
proc create_client_from_env(name) -> Client
```
Create client using SMP_HOST/SMP_PORT environment variables.

### Sync Operations

```sage
proc sync_state(client, target_id, state_data) -> bool
```
Send sync message with state data.

```sage
proc request_sync(client, target_id) -> bool
```
Request sync from target node.

## Usage Example

```sage
import smp.client

let client = create_client("my-node", "127.0.0.1", 42000)

# Connect
connect(client, "192.168.1.1", 42000)

# Register handlers
on(client, "1", proc(msg):
    print("Received data: " + str(msg["payload"]))
)

on(client, "*", proc(msg):
    print("Any message: " + str(msg))
)

# Send message
let seq = send(client, 2, {"data": "Hello"})

# Run event loop
run(client)
```

---

## Standalone Interactive Shell (`sagesmp`)

The unified `sagesmp` binary includes an interactive client shell for managing
devices connected to an SMP relay. A successful `connect` drops you straight into
this shell.

### Connect and Manage Devices

```bash
# Connect to a relay and enter the shell
./bin/sagesmp connect 192.168.254.44 42000

# One-shot: list connected devices without entering the shell
./bin/sagesmp devices 192.168.254.44 42000
```

### Shell Commands

| Command | Description |
|---------|-------------|
| `connect <host> <port>` | Open a real TCP connection to an SMP relay and switch to live mode |
| `devices [<host> <port>]` | List every device registered on the relay (id, platform, last-seen, telemetry) |
| `status` | Show live session state (relay host/port, your node ID) |
| `disconnect` | Close the relay connection and leave the shell |
| `send` / `broadcast` / `recv` | (Simulated) OTP-encrypted messaging against the in-process router |
| `relay on/off` / `relay add ...` | Configure auto-relay rules for incoming messages |
| `set secret/otp_pass/otp_seed` | Configure the OTP crypto used for simulated messaging |
| `help` / `quit` | Show command list / exit |

`devices` and `status` open their own real TCP connection to the relay (using
`SMP_HOST` / `SMP_PORT` if set) and are the standalone client's equivalent of the
dashboard's device-visibility features, implemented over the SMP relay protocol
rather than SSH.