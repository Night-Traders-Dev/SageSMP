gc_disable()

import tcp
import thread
import sys

let SMP_SECRET = "orangepi_cluster_secret_2026"
let argv = sys.args()
let RELAY_PORT = 42000
if len(argv) >= 3:
    RELAY_PORT = tonumber(argv[2])
end
import smp.core.smp_json as smp_json
let clients = {}
let clients_mutex = thread.mutex()

# Relay's own identity, advertised in device queries.
let RELAY_PLATFORM = "OrangePi"
let RELAY_INFO = "SageSMP central relay (port " + str(RELAY_PORT) + ")"

# Push a frame to a specific connected client by id (if its socket is open).
proc relay_send_to(client_id, frame):
    thread.lock(clients_mutex)
    let key = str(client_id)
    let ok = false
    if dict_has(clients, key):
        let c = clients[key]
        let fd = c["fd"]
        if fd != -1 and fd != 0:
            tcp.sendall(fd, frame)
            ok = true
        end
    end
    thread.unlock(clients_mutex)
    return ok
end

# Broadcast a frame to every connected client except the source.
proc relay_broadcast(from_id, frame, tag):
    thread.lock(clients_mutex)
    let ids = dict_keys(clients)
    let sent = 0
    for i in range(len(ids)):
        let c = clients[ids[i]]
        if c["id"] != from_id and c["fd"] != -1 and c["fd"] != 0:
            tcp.sendall(c["fd"], frame)
            sent = sent + 1
        end
    thread.unlock(clients_mutex)
    print("[BCAST] relayed to " + str(sent) + " peer(s)  " + tag)
    return sent
end

# Handle a single decoded message on a persistent client connection.
proc handle_message(client_fd, msg):
    let op = msg["op"]

    # ---- device query: gather relay + every registered device ----
    if op == "devices":
        thread.lock(clients_mutex)
        let ids = dict_keys(clients)
        let devs = []
        for i in range(len(ids)):
            push(devs, clients[ids[i]])
        thread.unlock(clients_mutex)
        let relay_self = {
            "id": -1, "platform": RELAY_PLATFORM, "info": RELAY_INFO,
            "services": nil, "compile": nil, "last_seen": clock(), "role": "relay"
        }
        let body = "\"devices\":" + smp_json.json_encode(devs) + ",\"relay\":" + smp_json.json_encode(relay_self)
        let resp = "{\"status\":\"ok\",\"op\":\"devices\"," + body + ",\"server_ts\":" + str(clock()) + "}"
        tcp.sendall(client_fd, resp)
        print("[DEVICE] query served -> " + str(len(devs)) + " device(s) + relay")
        return
    end

    # ---- directed send: route through the relay to a specific node ----
    if op == "send":
        let to_id = msg["to"]
        let from_id = msg["from"]
        let payload = msg["payload"]
        let pj = smp_json.json_encode(payload)
        let frame = "{\"op\":\"deliver\",\"from\":" + str(from_id)
        frame = frame + ",\"to\":" + str(to_id) + ",\"payload\":" + pj + "}"
        let ok = relay_send_to(to_id, frame)
        if ok:
            print("[SEND] node-" + str(from_id) + " -> node-" + str(to_id) + "  \"" + str(payload) + "\"")
        else:
            print("[WARN] send failed: node-" + str(to_id) + " not connected")
        end
        let ack = "{\"status\":\"ok\",\"op\":\"send_ack\",\"to\":" + str(to_id) + ",\"delivered\":" + str(ok) + "}"
        tcp.sendall(client_fd, ack)
        return
    end

    # ---- broadcast: relay to every other connected device ----
    if op == "broadcast":
        let from_id = msg["from"]
        let payload = msg["payload"]
        let frame = "{\"op\":\"deliver\",\"from\":" + str(from_id) + ",\"to\":0,\"payload\":" + smp_json.json_encode(payload) + ",\"broadcast\":true}"
        relay_broadcast(from_id, frame, "\"" + str(payload) + "\"")
        return
    end

    # ---- default: heartbeat / JOIN ----
    let cid = msg["client_id"]
    let platform = msg["platform"]
    let info_str = msg["info"]

    thread.lock(clients_mutex)
    clients[str(cid)] = {
        "id": cid, "platform": platform, "info": info_str, "fd": client_fd,
        "services": msg["services"], "compile": msg["compile"],
        "last_seen": clock(), "connected": true
    }
    let count = len(dict_keys(clients))
    thread.unlock(clients_mutex)

    print("[HEARTBEAT] " + platform + " (id=" + str(cid) + ") -> " + info_str)

    let services = msg["services"]
    if services != nil:
        print("[SERVICES] " + platform + " -> " + smp_json.json_encode(services))
    end

    let compile = msg["compile"]
    if compile != nil:
        print("[COMPILE] " + platform + " -> " + smp_json.json_encode(compile))
    end

    let resp = "{\"status\":\"ok\",\"node_count\":" + str(count) + ",\"server_ts\":" + str(clock()) + "}"
    tcp.sendall(client_fd, resp)
end

proc handle_client(client_fd):
    # Persistent connection: keep reading frames until the client disconnects.
    while true:
        let raw = tcp.recv(client_fd, 4096)
        if raw == nil or len(raw) == 0:
            break
        end
        let msg = smp_json.json_decode(raw)
        if msg == nil:
            tcp.sendall(client_fd, "{\"error\":\"bad json\"}")
            break
        end
        handle_message(client_fd, msg)
    end
    # Remove this client from the registry on disconnect.
    thread.lock(clients_mutex)
    let ids = dict_keys(clients)
    for i in range(len(ids)):
        if clients[ids[i]]["fd"] == client_fd:
            let c = clients[ids[i]]
            print("[DEVICE] " + str(c["platform"]) + " (id=" + str(c["id"]) + ") disconnected")
            dict_delete(clients, ids[i])
        end
    thread.unlock(clients_mutex)
    tcp.close(client_fd)
end

proc status_printer(_):
    while true:
        thread.sleep(60)
        thread.lock(clients_mutex)
        print("=== OrangePi Relay Status ===")
        let ids = dict_keys(clients)
        print("Connected clients: " + str(len(ids)))
        for i in range(len(ids)):
            let c = clients[ids[i]]
            print("  [" + c["platform"] + "] id=" + str(c["id"]) + " last_seen=" + str(c["last_seen"]) + " -> " + c["info"])
        end
        thread.unlock(clients_mutex)
    end
end

proc main():
    let port_str = sys.getenv("SMP_PORT")
    let port = RELAY_PORT
    if port_str != nil:
        port = tonumber(port_str)
    end

    print("=== OrangePi Relay Server (Real TCP) ===")
    print("Listening on 0.0.0.0:" + str(port))

    let listener = tcp.listen("0.0.0.0", port)
    if listener == -1:
        print("FATAL: Cannot listen on port " + str(port))
        return
    end

    thread.spawn(status_printer, nil)

    while true:
        let client_fd = tcp.accept(listener)
        if client_fd != -1:
            thread.spawn(handle_client, client_fd)
        end
    end

    tcp.close(listener)
end

main()
