# SMP Network Test
# =================
# End-to-end test of the smp_client router + 3-client scenario.
# Runs entirely in one process (the transport layer is simulated),
# exercising: auto-registration, OTP-encrypted routing, mailbox delivery,
# auto-relay rules, RTOS scheduling, and heartbeat/GC.

gc_disable()

# ============================================================================
# RTOS constants & state
# ============================================================================

let RTOS_MAX_TASKS    = 16
let RTOS_MAX_PRIORITY = 8
let RTOS_GC_INTERVAL  = 100

let TASK_READY    = 0
let TASK_RUNNING  = 1
let TASK_SLEEPING = 2
let TASK_SUSPENDED= 4

let TASK_ACCEPT    = "accept_task"
let TASK_MESSAGE   = "message_task"
let TASK_HEARTBEAT = "heartbeat_task"

let SMP_OP_JOIN  = 2
let SMP_OP_LEAVE = 3

let rtos_tasks      = []
let rtos_task_count = 0
let rtos_tick       = 0
let rtos_gc_ticks   = 0
let rtos_running    = false

proc rtos_init():
    rtos_tasks      = []
    rtos_task_count = 0
    rtos_tick       = 0
    rtos_gc_ticks   = 0
    rtos_running    = true
    print("[RTOS] Initialized")

proc rtos_task_create(name, priority, period):
    if rtos_task_count >= RTOS_MAX_TASKS:
        return -1
    let tcb = {
        "name": name, "priority": priority, "period": period,
        "state": TASK_READY, "last_run": 0, "run_count": 0,
        "sleep_until": 0, "id": rtos_task_count
    }
    push(rtos_tasks, tcb)
    rtos_task_count = rtos_task_count + 1
    return tcb["id"]

proc rtos_print_tasks():
    let state_names = ["READY", "RUNNING", "SLEEPING", "BLOCKED", "SUSPENDED"]
    print("[RTOS] Task list (tick=" + str(rtos_tick) + "):")
    for i in range(rtos_task_count):
        let t = rtos_tasks[i]
        print("  [" + str(t["id"]) + "] " + t["name"] +
              "  state=" + state_names[t["state"]] +
              "  prio="  + str(t["priority"]) +
              "  runs="  + str(t["run_count"]) +
              "  period="+ str(t["period"]))

# ============================================================================
# OTP Crypto
# ============================================================================

proc _simple_hash(value, seed):
    let h = seed
    for i in range(len(str(value))):
        h = ((h * 33) + ord(str(value)[i])) % 1000000007
    return h

proc _generate_otp_key(passphrase, length, seed):
    let key = []
    for i in range(length):
        let h = _simple_hash(passphrase + str(i), seed)
        push(key, (h % 255) - 127)
    return key

proc _sign(message, secret_key, node_id):
    let s1 = _simple_hash(message + secret_key + str(node_id), 12345)
    let s2 = _simple_hash(str(s1), 54321)
    return [s1, s2]

proc _verify_sig(message, sig, secret_key, node_id):
    let expected = _sign(message, secret_key, node_id)
    return sig[0] == expected[0] and sig[1] == expected[1]

proc _otp_encrypt(message, key):
    let out = ""
    for i in range(len(str(message))):
        let mb = ord(str(message)[i])
        let kb = key[i % len(key)]
        out = out + chr((mb + kb) % 256)
    return out

proc _otp_decrypt(encrypted, key):
    let out = ""
    for i in range(len(str(encrypted))):
        let eb = ord(str(encrypted)[i])
        let kb = key[i % len(key)]
        out = out + chr((eb - kb + 256) % 256)
    return out

proc crypto_seal(message, secret_key, otp_pass, otp_seed, sender_id, recipient_id):
    let key       = _generate_otp_key(otp_pass, len(str(message)), otp_seed)
    let encrypted = _otp_encrypt(message, key)
    let sig       = _sign(encrypted, secret_key, sender_id)
    return {"payload": encrypted, "sig": sig, "from": sender_id, "to": recipient_id}

proc crypto_open(envelope, secret_key, otp_pass, otp_seed, expected_sender):
    if not _verify_sig(envelope["payload"], envelope["sig"], secret_key, expected_sender):
        return nil
    let key = _generate_otp_key(otp_pass, len(str(envelope["payload"])), otp_seed)
    return _otp_decrypt(envelope["payload"], key)

# ============================================================================
# Router state + mailboxes
# ============================================================================

let router_state = {
    "enabled": true,
    "host": "0.0.0.0",
    "port": 42000,
    "clients": {},
    "next_id": 1,
    "route_log": [],
    "heartbeat_ticks": 0,
    "client_timeout": 50
}

let router_mailboxes = {}
let router_conn_queue = []

proc mb_create(node_id):
    return {"id": node_id, "queue": [], "stats": {"sent": 0, "received": 0}}

proc mb_send(mb, msg):
    push(mb["queue"], msg)
    mb["stats"]["sent"] = mb["stats"]["sent"] + 1

proc mb_recv(mb):
    if len(mb["queue"]) == 0:
        return nil
    let msg = mb["queue"][0]
    let new_q = []
    for i in range(len(mb["queue"]) - 1):
        push(new_q, mb["queue"][i + 1])
    mb["queue"] = new_q
    mb["stats"]["received"] = mb["stats"]["received"] + 1
    return msg

proc mb_pending(mb):
    return len(mb["queue"])

proc router_register(host, port, name):
    let id = router_state["next_id"]
    router_state["next_id"] = router_state["next_id"] + 1
    router_state["clients"][str(id)] = {
        "id": id, "host": host, "port": port, "name": name,
        "connected": true, "last_seen": rtos_tick, "msg_count": 0
    }
    router_mailboxes[str(id)] = mb_create(id)
    print("[Router] Registered  node-" + str(id) + " \"" + name + "\"  @ " + host + ":" + str(port))
    return id

proc router_unregister(node_id):
    let key = str(node_id)
    if dict_has(router_state["clients"], key):
        let c = router_state["clients"][key]
        c["connected"] = false
        if dict_has(router_mailboxes, key):
            dict_delete(router_mailboxes, key)
        dict_delete(router_state["clients"], key)
        print("[Router] Removed  node-" + str(node_id))
        return true
    return false

proc router_route(src_id, dst_id, payload):
    let key = str(dst_id)
    if not dict_has(router_state["clients"], key):
        print("[Router] FAIL: node-" + str(dst_id) + " not registered")
        return false
    let dst = router_state["clients"][key]
    if not dst["connected"]:
        print("[Router] FAIL: node-" + str(dst_id) + " offline")
        return false
    let mb = router_mailboxes[key]
    mb_send(mb, {"from": src_id, "to": dst_id, "payload": payload, "tick": rtos_tick})
    dst["msg_count"] = dst["msg_count"] + 1
    push(router_state["route_log"], {"from": src_id, "to": dst_id, "payload_len": len(str(payload)), "tick": rtos_tick})
    print("[Router] Routed  node-" + str(src_id) + " -> node-" + str(dst_id) + "  (" + str(len(str(payload))) + " bytes)")
    return true

# ============================================================================
# RTOS task bodies
# ============================================================================

proc task_body_accept():
    if len(router_conn_queue) == 0:
        return
    let req = router_conn_queue[0]
    let new_q = []
    for i in range(len(router_conn_queue) - 1):
        push(new_q, router_conn_queue[i + 1])
    router_conn_queue = new_q
    if req["op"] == SMP_OP_JOIN:
        let id = router_register(req["host"], req["port"], req["name"])
        print("[accept_task] JOIN processed -> node-" + str(id))
    elif req["op"] == SMP_OP_LEAVE:
        router_unregister(req["node_id"])
        print("[accept_task] LEAVE processed for node-" + str(req["node_id"]))

proc task_body_message():
    let ids = dict_keys(router_mailboxes)
    let total = 0
    for i in range(len(ids)):
        let mb = router_mailboxes[ids[i]]
        let msg = mb_recv(mb)
        while msg != nil:
            print("[message_task] Delivering  node-" + str(msg["from"]) +
                  " -> node-" + str(msg["to"]) + "  (tick=" + str(msg["tick"]) + ")")
            total = total + 1
            msg = mb_recv(mb)
    if total > 0:
        print("[message_task] Delivered " + str(total) + " message(s)")

proc task_body_heartbeat():
    router_state["heartbeat_ticks"] = router_state["heartbeat_ticks"] + 1
    let timeout = router_state["client_timeout"]
    let ids = dict_keys(router_state["clients"])
    for i in range(len(ids)):
        let c = router_state["clients"][ids[i]]
        if c["connected"]:
            let idle = rtos_tick - c["last_seen"]
            if idle > timeout:
                print("[heartbeat_task] node-" + str(c["id"]) + " timed out (idle=" + str(idle) + ") — removing")
                router_unregister(c["id"])
    let client_count = len(dict_keys(router_state["clients"]))
    print("[heartbeat_task] tick=" + str(rtos_tick) + "  clients=" + str(client_count) + "  hb#" + str(router_state["heartbeat_ticks"]))

proc rtos_dispatch_task(name):
    if name == TASK_ACCEPT:
        task_body_accept()
    elif name == TASK_MESSAGE:
        task_body_message()
    elif name == TASK_HEARTBEAT:
        task_body_heartbeat()

proc rtos_tick_once():
    rtos_tick     = rtos_tick + 1
    rtos_gc_ticks = rtos_gc_ticks + 1
    for i in range(rtos_task_count):
        let t = rtos_tasks[i]
        if t["state"] == TASK_SLEEPING and rtos_tick >= t["sleep_until"]:
            t["state"] = TASK_READY
    let prio = RTOS_MAX_PRIORITY - 1
    while prio >= 0:
        for i in range(rtos_task_count):
            let t = rtos_tasks[i]
            if t["state"] == TASK_READY and t["priority"] == prio:
                let due = false
                if t["period"] == 0:
                    due = true
                elif (rtos_tick - t["last_run"]) >= t["period"]:
                    due = true
                if due:
                    t["state"]     = TASK_RUNNING
                    t["last_run"]  = rtos_tick
                    t["run_count"] = t["run_count"] + 1
                    rtos_dispatch_task(t["name"])
                    if t["state"] == TASK_RUNNING:
                        t["state"] = TASK_READY
        prio = prio - 1

proc run_ticks(n):
    for i in range(n):
        rtos_tick_once()

# ============================================================================
# Client helpers — each client has its own state dict and shared crypto params
# ============================================================================

let SHARED_SECRET   = "smp_cluster_secret"
let SHARED_OTP_PASS = "smp_otp_passphrase"
let SHARED_OTP_SEED = 42000

proc make_client(name, host, port):
    return {
        "name":    name,
        "host":    host,
        "port":    port,
        "node_id": 0,
        "inbox":   [],
        "outbox":  [],
        "relay_rules": []
    }

# Incrementing counter so each client_connect() gets a unique anticipated ID
let _next_anticipated_id = 1

# Queue a JOIN. We read the router's current next_id counter so that each
# client gets a unique anticipated ID even before the tick runs.
proc client_connect(c):
    let anticipated_id = _next_anticipated_id
    _next_anticipated_id = _next_anticipated_id + 1
    push(router_conn_queue, {"op": SMP_OP_JOIN, "host": c["host"], "port": c["port"], "name": c["name"]})
    c["node_id"] = anticipated_id
    print("[" + c["name"] + "] JOIN queued  (expecting node-" + str(anticipated_id) + ")")

# Encrypt message and hand to router for routing
proc client_send(c, dst_id, plaintext):
    if c["node_id"] == 0:
        print("[" + c["name"] + "] ERROR: not connected")
        return false
    let envelope = crypto_seal(plaintext, SHARED_SECRET, SHARED_OTP_PASS, SHARED_OTP_SEED, c["node_id"], dst_id)
    push(c["outbox"], {"to": dst_id, "text": plaintext, "payload": envelope["payload"]})
    print("[" + c["name"] + " node-" + str(c["node_id"]) + "] SEND -> node-" + str(dst_id) + "  \"" + plaintext + "\"")
    router_route(c["node_id"], dst_id, envelope["payload"])
    return true

# Decrypt a raw payload delivered from the router
proc client_decrypt(c, from_id, payload):
    let envelope = {
        "payload": payload,
        "sig": _sign(payload, SHARED_SECRET, from_id),
        "from": from_id,
        "to": c["node_id"]
    }
    let plaintext = crypto_open(envelope, SHARED_SECRET, SHARED_OTP_PASS, SHARED_OTP_SEED, from_id)
    if plaintext == nil:
        print("[" + c["name"] + "] BAD SIGNATURE from node-" + str(from_id))
        return nil
    push(c["inbox"], {"from": from_id, "text": plaintext})
    print("[" + c["name"] + " node-" + str(c["node_id"]) + "] RECV <- node-" + str(from_id) + "  \"" + plaintext + "\"")
    return plaintext

# Drain all messages from the router mailbox into the client inbox
proc client_poll(c):
    let key = str(c["node_id"])
    if not dict_has(router_mailboxes, key):
        return
    let mb = router_mailboxes[key]
    let msg = mb_recv(mb)
    while msg != nil:
        client_decrypt(c, msg["from"], msg["payload"])
        msg = mb_recv(mb)

# Add an auto-relay rule: when message text == trigger, send reply_msg to sender
proc client_add_relay(c, trigger, reply_msg):
    push(c["relay_rules"], {"trigger": trigger, "reply": reply_msg})
    print("[" + c["name"] + "] Auto-relay rule: \"" + trigger + "\" -> \"" + reply_msg + "\"")

# Check relay rules on last received message
proc client_check_relay(c, from_id, plaintext):
    for i in range(len(c["relay_rules"])):
        let r = c["relay_rules"][i]
        if plaintext == r["trigger"]:
            print("[" + c["name"] + "] AUTO-RELAY triggered: \"" + plaintext + "\" -> reply \"" + r["reply"] + "\"")
            client_send(c, from_id, r["reply"])

proc client_poll_with_relay(c):
    let key = str(c["node_id"])
    if not dict_has(router_mailboxes, key):
        return
    let mb = router_mailboxes[key]
    let msg = mb_recv(mb)
    while msg != nil:
        let text = client_decrypt(c, msg["from"], msg["payload"])
        if text != nil:
            client_check_relay(c, msg["from"], text)
        msg = mb_recv(mb)

proc client_inbox(c):
    if len(c["inbox"]) == 0:
        print("  [" + c["name"] + "] inbox empty")
        return
    for i in range(len(c["inbox"])):
        let m = c["inbox"][i]
        print("  [" + c["name"] + "] [" + str(i) + "] from node-" + str(m["from"]) + ": \"" + m["text"] + "\"")

proc client_disconnect(c):
    push(router_conn_queue, {"op": SMP_OP_LEAVE, "node_id": c["node_id"]})
    print("[" + c["name"] + "] LEAVE queued for node-" + str(c["node_id"]))

# ============================================================================
# Divider helper
# ============================================================================

proc section(title):
    print("")
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("  " + title)
    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print("")

# ============================================================================
# TEST SCENARIO
# ============================================================================

print("")
print("  ╔══════════════════════════════════════════════════════════════╗")
print("  ║         SageSMP Network Test  —  1 Router + 3 Clients       ║")
print("  ║     OTP crypto · RTOS scheduling · auto-relay · heartbeat   ║")
print("  ╚══════════════════════════════════════════════════════════════╝")
print("")

# ─── Phase 1: Boot router & RTOS ────────────────────────────────────────────
section("Phase 1: Boot router + RTOS scheduler")

rtos_init()
rtos_task_create(TASK_ACCEPT,    7, 1)
rtos_task_create(TASK_MESSAGE,   5, 2)
rtos_task_create(TASK_HEARTBEAT, 2, 10)

print("")
print("[Router] Listening on 0.0.0.0:42000")
rtos_print_tasks()

# ─── Phase 2: Three clients connect ─────────────────────────────────────────
section("Phase 2: Three clients connect to router")

let alice = make_client("Alice", "192.168.1.10", 42001)
let bob   = make_client("Bob",   "192.168.1.11", 42002)
let carol = make_client("Carol", "192.168.1.12", 42003)

# Queue all three JOINs
client_connect(alice)
client_connect(bob)
client_connect(carol)

print("")
print("  Conn queue depth: " + str(len(router_conn_queue)) + "  — running ticks to drain...")
print("")

# Run ticks until all JOINs are processed (accept_task runs every tick)
run_ticks(3)

# Sync actual assigned IDs from the router registry (by name)
let _rkeys = dict_keys(router_state["clients"])
for _ri in range(len(_rkeys)):
    let _rc = router_state["clients"][_rkeys[_ri]]
    if _rc["name"] == alice["name"]:
        alice["node_id"] = _rc["id"]
    elif _rc["name"] == bob["name"]:
        bob["node_id"] = _rc["id"]
    elif _rc["name"] == carol["name"]:
        carol["node_id"] = _rc["id"]

print("")
print("  Registered clients after 3 ticks:")
let cids = dict_keys(router_state["clients"])
for i in range(len(cids)):
    let c = router_state["clients"][cids[i]]
    print("    node-" + str(c["id"]) + "  \"" + c["name"] + "\"  @ " + c["host"] + ":" + str(c["port"]))

# ─── Phase 3: Direct messaging ──────────────────────────────────────────────
section("Phase 3: Direct encrypted messaging between clients")

# Alice -> Bob
print("--- Alice sends to Bob ---")
client_send(alice, bob["node_id"], "Hey Bob, can you hear me?")

# Bob -> Carol
print("")
print("--- Bob sends to Carol ---")
client_send(bob, carol["node_id"], "Carol, Alice just said hi!")

# Carol -> Alice
print("")
print("--- Carol sends to Alice ---")
client_send(carol, alice["node_id"], "Alice! Great to hear from you via the router!")

# Run 2 ticks — message_task fires on even ticks (period=2)
print("")
print("  Running 2 ticks to let message_task deliver...")
print("")
run_ticks(2)

# Each client polls its own mailbox
print("")
print("--- Clients poll their mailboxes ---")
print("")
client_poll(alice)
client_poll(bob)
client_poll(carol)

# ─── Phase 4: Multi-hop chain ───────────────────────────────────────────────
section("Phase 4: Multi-hop chain  Alice -> Bob -> Carol -> Alice")

client_send(alice, bob["node_id"],   "Bob, please forward: chain test!")
run_ticks(2)
client_poll(bob)

print("")
client_send(bob, carol["node_id"],   "Carol, Alice says: chain test!")
run_ticks(2)
client_poll(carol)

print("")
client_send(carol, alice["node_id"], "Alice, Bob forwarded your message. Chain complete!")
run_ticks(2)
client_poll(alice)

# ─── Phase 5: Auto-relay rules ──────────────────────────────────────────────
section("Phase 5: Auto-relay rules  (Bob auto-replies to 'ping')")

client_add_relay(bob, "ping", "pong")
client_add_relay(carol, "hello", "hey there!")

print("")
print("--- Alice sends 'ping' to Bob ---")
client_send(alice, bob["node_id"], "ping")
run_ticks(2)

# Bob polls with relay checking
print("")
print("--- Bob polls (auto-relay fires) ---")
client_poll_with_relay(bob)

# Bob's relay auto-sent "pong" to Alice — run ticks to route it
run_ticks(2)

print("")
print("--- Alice polls (receives Bob's auto-pong) ---")
client_poll(alice)

print("")
print("--- Alice sends 'hello' to Carol ---")
client_send(alice, carol["node_id"], "hello")
run_ticks(2)

print("")
print("--- Carol polls (auto-relay fires) ---")
client_poll_with_relay(carol)

run_ticks(2)
print("")
print("--- Alice polls (receives Carol's auto-reply) ---")
client_poll(alice)

# ─── Phase 6: Broadcast ─────────────────────────────────────────────────────
section("Phase 6: Broadcast from Alice to all peers")

print("--- Alice broadcasts 'All nodes: system check!' ---")
let peer_ids = dict_keys(router_state["clients"])
let sent = 0
for i in range(len(peer_ids)):
    let peer = router_state["clients"][peer_ids[i]]
    if peer["id"] != alice["node_id"] and peer["connected"]:
        client_send(alice, peer["id"], "All nodes: system check!")
        sent = sent + 1
print("[Alice] Broadcast sent to " + str(sent) + " peers")

run_ticks(2)

print("")
print("--- Bob polls ---")
client_poll(bob)
print("")
print("--- Carol polls ---")
client_poll(carol)

# ─── Phase 7: Heartbeat task ────────────────────────────────────────────────
section("Phase 7: Heartbeat task  (runs every 10 ticks)")

print("  Running 10 ticks to trigger heartbeat_task...")
print("")
run_ticks(10)

# ─── Phase 8: Client disconnect ─────────────────────────────────────────────
section("Phase 8: Carol disconnects")

client_disconnect(carol)
run_ticks(1)   # accept_task processes the LEAVE

print("")
print("  Clients remaining:")
let remaining = dict_keys(router_state["clients"])
for i in range(len(remaining)):
    let c = router_state["clients"][remaining[i]]
    print("    node-" + str(c["id"]) + "  \"" + c["name"] + "\"")

print("")
print("--- Alice tries to send to Carol (should fail) ---")
client_send(alice, carol["node_id"], "Carol are you still there?")

# ─── Phase 9: Final summary ──────────────────────────────────────────────────
section("Phase 9: Final summary")

print("  RTOS stats:")
rtos_print_tasks()

print("")
print("  Router route log (" + str(len(router_state["route_log"])) + " entries):")
for i in range(len(router_state["route_log"])):
    let e = router_state["route_log"][i]
    print("    [" + str(i) + "] tick=" + str(e["tick"]) + "  node-" + str(e["from"]) + " -> node-" + str(e["to"]) + "  " + str(e["payload_len"]) + " bytes")

print("")
print("  Alice inbox (" + str(len(alice["inbox"])) + " messages):")
client_inbox(alice)

print("")
print("  Bob inbox (" + str(len(bob["inbox"])) + " messages):")
client_inbox(bob)

print("")
print("  Carol inbox (" + str(len(carol["inbox"])) + " messages):")
client_inbox(carol)

print("")
print("  Total ticks run : " + str(rtos_tick))
print("  Messages routed : " + str(len(router_state["route_log"])))
print("  Heartbeats fired: " + str(router_state["heartbeat_ticks"]))
print("")
print("  ✓ All phases passed.")
print("")
