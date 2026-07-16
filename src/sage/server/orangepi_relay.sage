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

proc handle_client(client_fd):
    let raw = tcp.recv(client_fd, 4096)

    if raw == nil or len(raw) == 0:
        tcp.close(client_fd)
        return
    end

    let msg = smp_json.json_decode(raw)
    if msg == nil:
        tcp.sendall(client_fd, "{\"error\":\"bad json\"}")
        tcp.close(client_fd)
        return
    end

    let op = msg["op"]
    if op == "list":
        # Device-management query: return the list of connected devices.
        thread.lock(clients_mutex)
        let ids = dict_keys(clients)
        let devs = []
        for i in range(len(ids)):
            push(devs, clients[ids[i]])
        thread.unlock(clients_mutex)
        let body = "\"devices\":" + smp_json.json_encode(devs)
        let resp = "{\"status\":\"ok\",\"op\":\"list\"," + body + ",\"server_ts\":" + str(clock()) + "}"
        tcp.sendall(client_fd, resp)
        tcp.recv(client_fd, 1)
        tcp.close(client_fd)
        return
    end

    let cid = msg["client_id"]
    let platform = msg["platform"]
    let info_str = msg["info"]

    thread.lock(clients_mutex)
    clients[str(cid)] = {
        "id": cid, "platform": platform, "info": info_str,
        "services": msg["services"], "compile": msg["compile"],
        "last_seen": clock()
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
    # Shift TIME_WAIT to client by waiting for client to close the connection first
    tcp.recv(client_fd, 1)
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
