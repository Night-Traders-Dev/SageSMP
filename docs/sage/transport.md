# Transport Module

Network transport layer for SMP communication with real native TCP socket support.

## Overview

The transport module provides low-level network primitives fully wired to real OS sockets via the native Sage `tcp` module:
- Native socket creation and lifecycle management
- Native TCP client/server connections
- Message framing with length prefixes
- Buffer management for framed messages
- Connection state lifecycle
- Heartbeat tracking

## API Reference

### Transport Modes
- `TRANSPORT_TCP` (0) - TCP transport
- `TRANSPORT_UDP` (1) - UDP transport
- `TRANSPORT_UNIX` (2) - Unix domain socket

### Socket Operations

```sage
proc create_socket() -> socket
```
Create socket wrapper dict.

```sage
proc connect(sock, host, port) -> bool
```
Connect socket to host:port.

```sage
proc bind(sock, host, port) -> bool
```
Bind socket to address.

```sage
proc listen(sock, backlog) -> bool
```
Start listening.

```sage
proc accept(sock) -> client_socket
```
Accept incoming connection.

```sage
proc send(sock, data) -> bytes_sent
```
Send data over socket.

```sage
proc recv(sock, size) -> data_or_nil
```
Receive up to size bytes.

```sage
proc close(sock)
```
Close socket.

### TCP Helpers

```sage
proc create_tcp_client(host, port) -> socket
```
Create and connect TCP client.

```sage
proc create_tcp_server(port) -> socket
```
Create TCP server bound to port.

### Message Framing

```sage
proc frame_message(msg) -> framed_string
```
Frame message with 8-digit length prefix.

```sage
proc parse_frame(buffer) -> {"ok": bool, "data": msg, "remaining": buffer}
```
Parse framed message from buffer.

### Buffer Management

```sage
proc create_buffer(initial_capacity) -> buffer
```
Create buffer dict.

```sage
proc write_buffer(buf, data) -> bool
```
Write data to buffer.

```sage
proc read_buffer(buf, size) -> data_or_nil
```
Read from buffer at position.

```sage
proc consume_buffer(buf, size) -> data_or_nil
```
Consume and return data from position.

```sage
proc reset_buffer(buf)
```
Reset buffer data and position.

### Connection Management

```sage
proc create_connection(node) -> connection
```
Create connection dict for a node.

```sage
proc open_connection(conn, host, port) -> connection
```
Open TCP connection.

```sage
proc close_connection(conn)
```
Close connection.

```sage
proc send_message(conn, msg) -> bool
```
Send framed message through connection.

```sage
proc recv_message(conn) -> data_or_nil
```
Receive message from connection.

```sage
proc ping(conn)
```
Update last heartbeat timestamp.

```sage
proc should_ping(conn, interval_secs) -> bool
```
Check if heartbeat should be sent.

### Heartbeat

```sage
proc create_heartbeat(interval_secs) -> heartbeat
```
Create heartbeat tracker.

```sage
proc update_heartbeat(hb)
```
Update last received timestamp.

```sage
proc check_heartbeat(hb) -> bool
```
Check if heartbeat timed out.

### Statistics

```sage
proc create_transport_stats() -> stats
```
Create transport statistics dict.

```sage
proc record_sent(stats, bytes)
proc record_recv(stats, bytes)
proc record_error(stats)
```