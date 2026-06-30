# Server Module

Server implementation for SMP protocol with relay support.

## Overview

The server module provides the `Server` class for accepting connections and routing messages, plus the `relay.sage` module for OTP-encrypted message forwarding.

## Server Class

### Methods

```sage
proc init(self, name, host, port)
```
Initialize server, create registry, mailboxes dict, and client tracking.

```sage
proc start(self)
```
Start listening for connections and handling messages.

```sage
proc stop(self)
```
Stop server and close socket.

```sage
proc handle_client(self, client)
```
Handle messages from connected client.

```sage
proc handle_message(self, client, raw_msg)
```
Process incoming protocol messages.

```sage
proc handle_join(self, client, msg)
```
Process JOIN message, register node.

```sage
proc handle_leave(self, client, msg)
```
Process LEAVE message, cleanup node.

```sage
proc handle_message_data(self, client, msg)
```
Route message data to target mailbox.

```sage
proc route_message(self, sender_id, target_id, payload)
```
Route message to specific target.

```sage
proc broadcast(self, payload)
```
Broadcast to all connected clients.

```sage
proc on(self, event, handler)
```
Register event handler.

### Factory Functions

```sage
proc create_server(name, host, port) -> Server
proc create_server_from_env(name) -> Server
```

### Cluster Functions

```sage
proc create_cluster(servers) -> cluster
proc elect_leader(cluster) -> node_or_nil
proc get_leader(cluster) -> node_or_nil
proc is_leader(cluster, server) -> bool
```

### Routing Functions

```sage
proc route_to_node(server, node_id) -> mailbox_or_nil
proc broadcast_to_all(server, payload)
proc send_to_node(server, node_id, payload)
```

## Relay Module

The relay module (`src/sage/server/relay.sage`) provides OTP-encrypted message forwarding.

### OTP Functions

```sage
proc simple_hash(value, seed) -> int
```
Pure Sage hash for key derivation.

```sage
proc generate_otp_key(passphrase, length, seed) -> [int, ...]
```
Generate OTP key from passphrase.

```sage
proc otp_encrypt(message, otp_key) -> encrypted_string
proc otp_decrypt(encrypted, otp_key) -> decrypted_string
```
OTP encrypt/decrypt operations.

```sage
proc sign_message(message, secret_key, node_id) -> [int, int]
proc verify_signature(message, signature, secret_key, node_id) -> bool
```
Hash-based signing.

### Secure Message

```sage
proc create_secure_message(message, secret_key, otp_pass, otp_seed, sender_id, recipient_id) -> envelope
```
Create OTP-encrypted envelope.

```sage
proc read_secure_message(msg, secret_key, otp_pass, otp_seed, expected_sender) -> payload_or_nil
```
Verify and decrypt envelope.

### Relay Rules

```sage
proc add_relay_rule(trigger_msg, target_host, target_port, forward_msg, secret_key, otp_pass, otp_seed) -> index
```
Add rule: when trigger_msg received, forward forward_msg encrypted.

```sage
proc secure_forward(msg, rule) -> envelope
```
Create encrypted envelope from rule.

```sage
proc relay_process_message(msg) -> envelope_or_nil
```
Process incoming message against all rules.

```sage
proc list_relay_rules()
```
Print all configured rules.

## Usage Example

```sage
import smp.server.relay

# Configure relay rules
add_relay_rule("hello", "192.168.1.100", 42001, "Hello!", "key", "pass", 100)

# Process messages
let msg = {"sender_id": 1, "payload": "hello"}
let forwarded = relay_process_message(msg)
```