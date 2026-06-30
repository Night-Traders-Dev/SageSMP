# Mailbox Module

Thread-safe mailbox system for inter-node message passing with FIFO delivery.

## Overview

The mailbox module provides a complete message queuing system inspired by Erlang-style mailboxes. It supports:
- FIFO message delivery
- Acknowledge tracking
- Message handlers for automatic processing
- Statistics collection
- Multi-mailbox operations

## API Reference

### Message Creation

```sage
proc create_message(sender_id, recipient_id, msg_type, payload) -> message
```
Creates a message envelope with sender, recipient, type, and payload.

### Mailbox Creation

```sage
proc create_mailbox(node_id, capacity) -> mailbox
```
Creates a mailbox with specified node ID and capacity (0 = unlimited).

```sage
proc create_mailbox_with_handlers(node_id, capacity, handlers) -> mailbox
```
Creates a mailbox with pre-registered handlers.

### Sending Messages

```sage
proc send(mailbox, message) -> seq
```
Send a message to mailbox. Returns sequence number. Raises error if full/closed.

```sage
proc send_with_ack(mailbox, message) -> seq
```
Send with acknowledgment tracking.

```sage
proc try_send(mailbox, message) -> bool
```
Non-blocking send. Returns false if mailbox full/closed.

### Receiving Messages

```sage
proc recv(mailbox) -> message
```
Receive message in FIFO order. Returns nil if empty/closed.

```sage
proc try_recv(mailbox) -> {"ok": bool, "value": message}
```
Non-blocking receive with ok flag.

```sage
proc peek(mailbox) -> message
```
Peek at next message without removing it.

### Acknowledgment

```sage
proc ack(mailbox, seq) -> bool
```
Acknowledge receipt of message by sequence number.

```sage
proc pending_acks(mailbox) -> [seq, ...]
```
Get list of pending acknowledgment sequence numbers.

### Handlers

```sage
proc on_mail(mailbox, msg_type, handler)
```
Register handler for specific message type.

```sage
proc on_any(mailbox, handler)
```
Register handler for any message type.

```sage
proc process(mailbox)
```
Process all pending messages through registered handlers.

### Lifecycle

```sage
proc close(mailbox)
```
Close mailbox (no more sends/receives).

```sage
proc is_closed(mailbox) -> bool
```
Check if mailbox is closed.

```sage
proc clear(mailbox)
```
Clear all pending messages.

```sage
proc status(mailbox) -> dict
```
Get mailbox status: id, pending count, closed, stats.

### Statistics

```sage
proc get_stats(mailbox) -> {"sent": n, "received": n, "acked": n, "dropped": n, "errors": n}
```
Get mailbox statistics.

```sage
proc reset_stats(mailbox)
```
Reset statistics to zero.

### Multi-mailbox Operations

```sage
proc broadcast(mailboxes, message) -> [seq, ...]
```
Broadcast message to all mailboxes (except sender).

```sage
proc route(mailboxes, message) -> seq
```
Route message to specific recipient by ID.

```sage
proc drain(mailbox) -> [messages, ...]
```
Drain all messages from mailbox into array.

## Usage Example

```sage
import smp.mailbox

# Create mailbox
let mbox = create_mailbox(1, 100)

# Register handler
on_mail(mbox, MSG_TYPE_DATA, proc(msg):
    print("Received: " + str(msg["payload"]))
)

# Send message
let msg = create_message(1, 2, MSG_TYPE_DATA, "Hello!")
send(mbox, msg)

# Process messages
process(mbox)

# Check stats
print("Sent: " + str(get_stats(mbox)["sent"]))
```