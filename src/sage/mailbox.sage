# SMP Mailbox System
# ==================
# Thread-safe mailbox for inter-node message passing

gc_disable()

# ============================================================================
# Mailbox Types
# ============================================================================

# Mailbox message envelope
# Each message has: sender_id, recipient_id, msg_type, payload, timestamp, seq
proc create_message(sender_id, recipient_id, msg_type, payload):
    let msg = {}
    msg["sender_id"] = sender_id
    msg["recipient_id"] = recipient_id
    msg["type"] = msg_type
    msg["payload"] = payload
    msg["timestamp"] = clock()
    msg["seq"] = 0
    msg["ack"] = false
    return msg

# ============================================================================
# Mailbox Creation and Management
# ============================================================================

proc create_mailbox(node_id, capacity):
    let mailbox = {}
    mailbox["id"] = node_id
    mailbox["queue"] = []
    mailbox["capacity"] = capacity
    mailbox["closed"] = false
    mailbox["seq_counter"] = 0
    mailbox["pending_acks"] = {}
    mailbox["stats"] = {
        "sent": 0,
        "received": 0,
        "acked": 0,
        "dropped": 0,
        "errors": 0
    }
    return mailbox

proc create_mailbox_with_handlers(node_id, capacity, handlers):
    let mb = create_mailbox(node_id, capacity)
    mb["handlers"] = handlers
    return mb

# ============================================================================
# Message Sending
# ============================================================================

# Send a message to a mailbox
proc send(mailbox, message):
    if mailbox["closed"]:
        mailbox["stats"]["dropped"] = mailbox["stats"]["dropped"] + 1
        raise "mailbox closed"
    
    if mailbox["capacity"] > 0 and len(mailbox["queue"]) >= mailbox["capacity"]:
        mailbox["stats"]["dropped"] = mailbox["stats"]["dropped"] + 1
        raise "mailbox full"
    
    mailbox["seq_counter"] = mailbox["seq_counter"] + 1
    message["seq"] = mailbox["seq_counter"]
    
    push(mailbox["queue"], message)
    mailbox["stats"]["sent"] = mailbox["stats"]["sent"] + 1
    return message["seq"]

# Send with acknowledgment tracking
proc send_with_ack(mailbox, message):
    let seq = send(mailbox, message)
    mailbox["pending_acks"][str(seq)] = message
    return seq

# Try to send (non-blocking)
proc try_send(mailbox, message):
    if mailbox["closed"] or (mailbox["capacity"] > 0 and len(mailbox["queue"]) >= mailbox["capacity"]):
        return false
    send(mailbox, message)
    return true

# ============================================================================
# Message Receiving
# ============================================================================

# Receive a message from mailbox (FIFO)
proc recv(mailbox):
    if len(mailbox["queue"]) == 0:
        if mailbox["closed"]:
            return nil
        return nil
    
    let msg = mailbox["queue"][0]
    let new_queue = []
    for i in range(len(mailbox["queue"]) - 1):
        push(new_queue, mailbox["queue"][i + 1])
    mailbox["queue"] = new_queue
    mailbox["stats"]["received"] = mailbox["stats"]["received"] + 1
    return msg

# Try to receive (non-blocking, returns dict with ok flag)
proc try_recv(mailbox):
    if len(mailbox["queue"]) == 0:
        let result = {}
        result["ok"] = false
        result["value"] = nil
        return result
    
    let msg = recv(mailbox)
    let result = {}
    result["ok"] = true
    result["value"] = msg
    return result

# Peek at next message without removing
proc peek(mailbox):
    if len(mailbox["queue"]) == 0:
        return nil
    return mailbox["queue"][0]

# ============================================================================
# Acknowledgment Handling
# ============================================================================

# Acknowledge receipt of a message
proc ack(mailbox, seq):
    let key = str(seq)
    if dict_has(mailbox["pending_acks"], key):
        mailbox["pending_acks"][key]["ack"] = true
        dict_delete(mailbox["pending_acks"], key)
        mailbox["stats"]["acked"] = mailbox["stats"]["acked"] + 1
        return true
    return false

# Check for unacknowledged messages
proc pending_acks(mailbox):
    return dict_keys(mailbox["pending_acks"])

# ============================================================================
# Handler Registration
# ============================================================================

# Register a handler for a message type
proc on_mail(mailbox, msg_type, handler):
    if not dict_has(mailbox, "handlers"):
        mailbox["handlers"] = {}
    if not dict_has(mailbox["handlers"], msg_type):
        mailbox["handlers"][msg_type] = []
    push(mailbox["handlers"][msg_type], handler)

# Register a default handler for any message type
proc on_any(mailbox, handler):
    if not dict_has(mailbox, "handlers"):
        mailbox["handlers"] = {}
    if not dict_has(mailbox["handlers"], "*"):
        mailbox["handlers"]["*"] = []
    push(mailbox["handlers"]["*"], handler)

# Process all pending messages through handlers
proc process(mailbox):
    while len(mailbox["queue"]) > 0:
        let msg = recv(mailbox)
        if dict_has(mailbox, "handlers"):
            let msg_type = str(msg["type"])
            if dict_has(mailbox["handlers"], msg_type):
                let handlers = mailbox["handlers"][msg_type]
                for i in range(len(handlers)):
                    handlers[i](msg)
            elif dict_has(mailbox["handlers"], "*"):
                let handlers = mailbox["handlers"]["*"]
                for i in range(len(handlers)):
                    handlers[i](msg)

# ============================================================================
# Mailbox Lifecycle
# ============================================================================

# Close mailbox for sending/receiving
proc close(mailbox):
    mailbox["closed"] = true

# Check if mailbox is closed
proc is_closed(mailbox):
    return mailbox["closed"]

# Get mailbox status
proc status(mailbox):
    let s = {}
    s["id"] = mailbox["id"]
    s["pending"] = len(mailbox["queue"])
    s["closed"] = mailbox["closed"]
    s["stats"] = mailbox["stats"]
    return s

# Clear all pending messages
proc clear(mailbox):
    mailbox["queue"] = []

# ============================================================================
# Mailbox Statistics
# ============================================================================

proc get_stats(mailbox):
    return mailbox["stats"]

proc reset_stats(mailbox):
    mailbox["stats"] = {
        "sent": 0,
        "received": 0,
        "acked": 0,
        "dropped": 0,
        "errors": 0
    }

# ============================================================================
# Multi-mailbox Operations (Multiple cores/nodes)
# ============================================================================

# Broadcast message to all mailboxes
proc broadcast(mailboxes, message):
    let seqs = []
    for i in range(len(mailboxes)):
        let target_mb = mailboxes[i]
        if target_mb["id"] != message["sender_id"]:
            push(seqs, send(target_mb, message))
    return seqs

# Route message to specific recipient by ID
proc route(mailboxes, message):
    for i in range(len(mailboxes)):
        if mailboxes[i]["id"] == message["recipient_id"]:
            return send(mailboxes[i], message)
    raise "no mailbox found for recipient: " + str(message["recipient_id"])

# Drain all messages from mailbox into array
proc drain(mailbox):
    let msgs = []
    while len(mailbox["queue"]) > 0:
        push(msgs, recv(mailbox))
    return msgs