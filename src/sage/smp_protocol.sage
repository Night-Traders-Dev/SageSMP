# SMP Protocol Definitions
# ========================
# Core protocol structures and utilities

gc_disable()

let SMP_OP_HEARTBEAT = 0
let SMP_OP_MESSAGE = 1
let SMP_OP_JOIN = 2
let SMP_OP_LEAVE = 3
let SMP_OP_MAILBOX = 4
let SMP_OP_MAILBOX_ACK = 5
let SMP_OP_SYNC = 6
let SMP_OP_SYNC_ACK = 7
let SMP_OP_BROADCAST = 8
let SMP_OP_NODE_INFO = 9
let SMP_VERSION = "1.0.0"

# ============================================================================
# Protocol Message Builder
# ============================================================================

# Build a protocol message
proc build_message(opcode, sender_id, target_id, payload):
    let msg = {}
    msg["op"] = opcode
    msg["sender"] = sender_id
    msg["target"] = target_id
    msg["payload"] = payload
    msg["timestamp"] = clock()
    msg["id"] = 0
    return msg

# Build heartbeat message
proc build_heartbeat(sender_id, seq):
    let msg = build_message(SMP_OP_HEARTBEAT, sender_id, 0, {"seq": seq})
    return msg

# Build data message
proc build_data(sender_id, target_id, data):
    let msg = build_message(SMP_OP_MESSAGE, sender_id, target_id, data)
    return msg

# Build join request
proc build_join(sender_id, node_info):
    let msg = build_message(SMP_OP_JOIN, sender_id, 0, node_info)
    return msg

# Build leave notification
proc build_leave(sender_id):
    let msg = build_message(SMP_OP_LEAVE, sender_id, 0, nil)
    return msg

# Build mailbox transfer
proc build_mailbox(sender_id, target_id, mbox_data):
    let msg = build_message(SMP_OP_MAILBOX, sender_id, target_id, mbox_data)
    return msg

# Build sync request
proc build_sync(sender_id, target_id, state):
    let msg = build_message(SMP_OP_SYNC, sender_id, target_id, state)
    return msg

# Build broadcast message
proc build_broadcast(sender_id, payload):
    let msg = build_message(SMP_OP_BROADCAST, sender_id, 0, payload)
    return msg

# ============================================================================
# Message Encoding/Decoding
# ============================================================================

# Encode message to string for transmission
proc encode(msg):
    # Simple JSON-style encoding (Sage native)
    let result = "{"
    result = result + "\"op\":" + str(msg["op"]) + ","
    result = result + "\"sender\":" + str(msg["sender"]) + ","
    result = result + "\"target\":" + str(msg["target"]) + ","
    result = result + "\"ts\":" + str(msg["timestamp"])
    
    # Encode payload if present
    if msg["payload"] != nil:
        if type(msg["payload"]) == "String":
            result = result + ",\"payload\":\"" + msg["payload"] + "\""
        elif type(msg["payload"]) == "Number":
            result = result + ",\"payload\":" + str(msg["payload"])
        else:
            result = result + ",\"payload\":\"" + str(msg["payload"]) + "\""
        end
    end
    
    result = result + "}"
    return result

# Decode encoded message string back to dict
proc decode(encoded):
    let msg = {}
    # Simple parsing - in real implementation would use json module
    # For now, returns the encoded string wrapped
    msg["raw"] = encoded
    msg["decoded_at"] = clock()
    return msg

# ============================================================================
# Protocol Validation
# ============================================================================

# Validate a protocol message
proc validate(msg):
    if not dict_has(msg, "op"):
        return false
    if not dict_has(msg, "sender"):
        return false
    if not dict_has(msg, "target"):
        return false
    if msg["op"] < 0 or msg["op"] > 10:
        return false
    return true

# Get opcode name from numeric opcode
proc opcode_name(opcode):
    if opcode == SMP_OP_HEARTBEAT:
        return "HEARTBEAT"
    elif opcode == SMP_OP_MESSAGE:
        return "MESSAGE"
    elif opcode == SMP_OP_JOIN:
        return "JOIN"
    elif opcode == SMP_OP_LEAVE:
        return "LEAVE"
    elif opcode == SMP_OP_MAILBOX:
        return "MAILBOX"
    elif opcode == SMP_OP_MAILBOX_ACK:
        return "MAILBOX_ACK"
    elif opcode == SMP_OP_SYNC:
        return "SYNC"
    elif opcode == SMP_OP_SYNC_ACK:
        return "SYNC_ACK"
    elif opcode == SMP_OP_BROADCAST:
        return "BROADCAST"
    elif opcode == SMP_OP_NODE_INFO:
        return "NODE_INFO"
    else:
        return "UNKNOWN"

# ============================================================================
# Sequence Management
# ============================================================================

proc create_sequence_tracker():
    let tracker = {}
    tracker["last_sent"] = 0
    tracker["last_received"] = 0
    tracker["expected_next"] = 1
    tracker["missing"] = []
    return tracker

proc next_seq(tracker):
    tracker["last_sent"] = tracker["last_sent"] + 1
    return tracker["last_sent"]

proc validate_seq(tracker, seq):
    if seq == tracker["expected_next"]:
        tracker["expected_next"] = tracker["expected_next"] + 1
        return true
    elif seq > tracker["expected_next"]:
        push(tracker["missing"], tracker["expected_next"])
        tracker["expected_next"] = seq + 1
        return true
    else:
        # Duplicate or old sequence
        return false

proc record_received(tracker, seq):
    tracker["last_received"] = seq
    return seq

# ============================================================================
# State Management
# ============================================================================

proc create_state():
    let state = {}
    state["nodes"] = {}
    state["mailboxes"] = {}
    state["seq_trackers"] = {}
    state["version"] = SMP_VERSION
    state["created"] = clock()
    return state

proc add_node(state, node_id, node_info):
    state["nodes"][str(node_id)] = node_info

proc remove_node(state, node_id):
    if dict_has(state["nodes"], str(node_id)):
        dict_delete(state["nodes"], str(node_id))
        return true
    return false

proc get_node(state, node_id):
    if dict_has(state["nodes"], str(node_id)):
        return state["nodes"][str(node_id)]
    return nil

proc node_count(state):
    return len(dict_keys(state["nodes"]))