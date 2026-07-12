gc_disable()

import tcp
import thread
import sys

let SMP_SECRET = "orangepi_cluster_secret_2026"
let RELAY_PORT = 42000
let DQ = chr(34)

proc json_escape(s):
    let r = replace(s, chr(92), chr(92) + chr(92))
    r = replace(r, chr(34), chr(92) + chr(34))
    return r

proc json_encode(val):
    let t = type(val)
    if t == "nil":
        return "null"
    if t == "number":
        return str(val)
    if t == "string":
        return DQ + json_escape(val) + DQ
    if t == "array":
        let parts = ["["]
        for i in range(len(val)):
            if i > 0: push(parts, ",")
            push(parts, json_encode(val[i]))
        push(parts, "]")
        return join(parts, "")
    if t == "dict":
        let parts = ["{"]
        let keys = dict_keys(val)
        for i in range(len(keys)):
            if i > 0: push(parts, ",")
            push(parts, DQ + keys[i] + DQ + ":")
            push(parts, json_encode(val[keys[i]]))
        push(parts, "}")
        return join(parts, "")
    return DQ + json_escape(str(val)) + DQ

proc json_decode(raw):
    if raw == nil or len(raw) == 0:
        return nil
    let i = 0
    let n = len(raw)
    while i < n and (raw[i] == " " or raw[i] == chr(10) or raw[i] == chr(13) or raw[i] == chr(9)):
        i = i + 1
    if raw[i] != "{":
        return nil
    let result = {}
    i = i + 1
    while i < n and raw[i] != "}":
        while i < n and (raw[i] == " " or raw[i] == chr(10) or raw[i] == chr(13) or raw[i] == chr(9) or raw[i] == ","):
            i = i + 1
        if raw[i] == "}":
            break
        if raw[i] != DQ:
            return nil
        i = i + 1
        let key = ""
        while i < n and raw[i] != DQ:
            if raw[i] == chr(92):
                i = i + 1
            key = key + raw[i]
            i = i + 1
        i = i + 1
        while i < n and (raw[i] == " " or raw[i] == ":"):
            i = i + 1
        if raw[i] == DQ:
            i = i + 1
            let val_str = ""
            while i < n and raw[i] != DQ:
                if raw[i] == chr(92):
                    i = i + 1
                val_str = val_str + raw[i]
                i = i + 1
            i = i + 1
            result[key] = val_str
        elif raw[i] == "[":
            i = i + 1
            let arr = []
            while i < n:
                while i < n and (raw[i] == " " or raw[i] == "," or raw[i] == chr(10) or raw[i] == chr(13)):
                    i = i + 1
                if i >= n or raw[i] == "]":
                    break
                if raw[i] == DQ:
                    i = i + 1
                    let s = ""
                    while i < n and raw[i] != DQ:
                        s = s + raw[i]
                        i = i + 1
                    i = i + 1
                    push(arr, s)
                else:
                    let num_str = ""
                    while i < n and ((raw[i] >= "0" and raw[i] <= "9") or raw[i] == "." or raw[i] == "-"):
                        num_str = num_str + raw[i]
                        i = i + 1
                    if len(num_str) > 0:
                        push(arr, tonumber(num_str))
            i = i + 1
            result[key] = arr
        elif raw[i] == "t" or raw[i] == "f":
            if raw[i] == "t":
                result[key] = 1
                i = i + 4
            else:
                result[key] = 0
                i = i + 5
        elif raw[i] == "n":
            result[key] = nil
            i = i + 4
        else:
            let num_str = ""
            while i < n and ((raw[i] >= "0" and raw[i] <= "9") or raw[i] == "." or raw[i] == "-" or raw[i] == "+" or raw[i] == "e" or raw[i] == "E"):
                num_str = num_str + raw[i]
                i = i + 1
            if len(num_str) > 0:
                result[key] = tonumber(num_str)
    return result

let clients = {}
let clients_mutex = thread.mutex()

proc handle_client(client_fd):
    let raw = tcp.recv(client_fd, 4096)

    if raw == nil or len(raw) == 0:
        tcp.close(client_fd)
        return
    end

    let msg = json_decode(raw)
    if msg == nil:
        tcp.sendall(client_fd, "{\"error\":\"bad json\"}")
        tcp.close(client_fd)
        return
    end

    let cid = msg["client_id"]
    let platform = msg["platform"]
    let info_str = msg["info"]

    thread.lock(clients_mutex)
    clients[str(cid)] = {"id": cid, "platform": platform, "info": info_str, "last_seen": clock()}
    let count = len(dict_keys(clients))
    thread.unlock(clients_mutex)

    print("[HEARTBEAT] " + platform + " (id=" + str(cid) + ") -> " + info_str)

    let resp = "{\"status\":\"ok\",\"node_count\":" + str(count) + ",\"server_ts\":" + str(clock()) + "}"
    tcp.sendall(client_fd, resp)
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
