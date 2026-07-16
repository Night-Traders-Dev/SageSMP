import sys
import tcp
import thread
import io

proc substring(s, start, length):
    let res = ""
    for i in range(length):
        if start + i < len(s):
            res = res + s[start + i]
        end
    end
    return res


# =========================================
# src/sage/core/smp_json.sage
# =========================================
let DQ = chr(34)

proc json_escape(s):
    let r = replace(s, chr(92), chr(92) + chr(92))
    r = replace(r, chr(34), chr(92) + chr(34))
    r = replace(r, chr(10), chr(92) + "n")
    r = replace(r, chr(9), chr(92) + "t")
    r = replace(r, chr(13), chr(92) + "r")
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

proc json_skip_ws(raw, i, n):
    while i < n and (raw[i] == " " or raw[i] == chr(10) or raw[i] == chr(13) or raw[i] == chr(9)):
        i = i + 1
    end
    return i

proc json_parse_value(raw, i, n):
    i = json_skip_ws(raw, i, n)
    if i >= n:
        return {"value": nil, "next": i}
    end
    let c = raw[i]
    if c == "{":
        let obj = {}
        i = i + 1
        i = json_skip_ws(raw, i, n)
        if i < n and raw[i] == "}":
            return {"value": obj, "next": i + 1}
        end
        while i < n:
            i = json_skip_ws(raw, i, n)
            if i >= n or raw[i] == "}":
                break
            end
            if raw[i] != DQ:
                return {"value": nil, "next": i}
            end
            i = i + 1
            let key = ""
            while i < n and raw[i] != DQ:
                if raw[i] == chr(92):
                    i = i + 1
                end
                key = key + raw[i]
                i = i + 1
            end
            i = i + 1
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ":":
                i = i + 1
            end
            let res = json_parse_value(raw, i, n)
            obj[key] = res["value"]
            i = res["next"]
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ",":
                i = i + 1
            end
        end
        if i < n and raw[i] == "}":
            i = i + 1
        end
        return {"value": obj, "next": i}
    elif c == "[":
        let arr = []
        i = i + 1
        i = json_skip_ws(raw, i, n)
        if i < n and raw[i] == "]":
            return {"value": arr, "next": i + 1}
        end
        while i < n:
            i = json_skip_ws(raw, i, n)
            if i >= n or raw[i] == "]":
                break
            end
            let res = json_parse_value(raw, i, n)
            push(arr, res["value"])
            i = res["next"]
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ",":
                i = i + 1
            end
        end
        if i < n and raw[i] == "]":
            i = i + 1
        end
        return {"value": arr, "next": i}
    elif c == DQ:
        i = i + 1
        let s = ""
        while i < n and raw[i] != DQ:
            if raw[i] == chr(92):
                i = i + 1
                if i < n:
                    let ec = raw[i]
                    if ec == "n":
                        s = s + chr(10)
                    elif ec == "t":
                        s = s + chr(9)
                    elif ec == "r":
                        s = s + chr(13)
                    else:
                        s = s + chr(92) + ec
                    end
                    i = i + 1
                end
            else:
                s = s + raw[i]
                i = i + 1
            end
        end
        if i < n and raw[i] == DQ:
            i = i + 1
        end
        return {"value": s, "next": i}
    elif c == "t":
        return {"value": 1, "next": i + 4}
    elif c == "f":
        return {"value": 0, "next": i + 5}
    elif c == "n":
        return {"value": nil, "next": i + 4}
    else:
        let num_str = ""
        while i < n and ((raw[i] >= "0" and raw[i] <= "9") or raw[i] == "." or raw[i] == "-" or raw[i] == "+" or raw[i] == "e" or raw[i] == "E"):
            num_str = num_str + raw[i]
            i = i + 1
        end
        if len(num_str) > 0:
            return {"value": tonumber(num_str), "next": i}
        end
        return {"value": nil, "next": i}
    end

proc json_decode(raw):
    if raw == nil or len(raw) == 0:
        return nil
    end
    let n = len(raw)
    let res = json_parse_value(raw, 0, n)
    return res["value"]

# =========================================
# src/sage/server/orangepi_relay.sage
# =========================================


let SMP_SECRET = "orangepi_cluster_secret_2026"
let RELAY_PORT = 42000
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

    let op = msg["op"]
    if op == "list":
        thread.lock(clients_mutex)
        let ids = dict_keys(clients)
        let devs = []
        for i in range(len(ids)):
            push(devs, clients[ids[i]])
        thread.unlock(clients_mutex)
        let resp = "{\"status\":\"ok\",\"op\":\"list\",\"devices\":" + json_encode(devs) + ",\"server_ts\":" + str(clock()) + "}"
        tcp.sendall(client_fd, resp)
        tcp.recv(client_fd, 1)
        tcp.close(client_fd)
        return
    end

    let cid = msg["client_id"]
    let platform = msg["platform"]
    let info_str = msg["info"]

    thread.lock(clients_mutex)
    clients[str(cid)] = {"id": cid, "platform": platform, "info": info_str, "services": msg["services"], "compile": msg["compile"], "last_seen": clock()}
    let count = len(dict_keys(clients))
    thread.unlock(clients_mutex)

    print("[HEARTBEAT] " + platform + " (id=" + str(cid) + ") -> " + info_str)

    let services = msg["services"]
    if services != nil:
        print("[SERVICES] " + platform + " -> " + json_encode(services))
    end

    let compile = msg["compile"]
    if compile != nil:
        print("[COMPILE] " + platform + " -> " + json_encode(compile))
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

proc run_orangepi(mode_idx):
    let argv = sys.args()
    if len(argv) >= mode_idx + 2:
        RELAY_PORT = tonumber(argv[mode_idx + 1])
    end
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


# =========================================
# Connect to an OrangePi-style SMP relay server (real TCP)
# =========================================
# Sends a single heartbeat JSON frame and prints the server's response
# ({"status":"ok","node_count":N,"server_ts":T}). Mirrors the rpi2/rpi4
# heartbeat so the standalone binary can verify connectivity to a live server.

proc run_connect(mode_idx):
    let argv = sys.args()
    if len(argv) < mode_idx + 3:
        print("Usage: sagesmp connect <host> <port>")
        return
    end
    let host = argv[mode_idx + 1]
    let port = tonumber(argv[mode_idx + 2])
    if port == nil or port < 1 or port > 65535:
        print("Error: port must be 1-65535")
        return
    end

    let host_env = sys.getenv("SMP_HOST")
    if host_env != nil:
        host = host_env
    end
    let port_env = sys.getenv("SMP_PORT")
    if port_env != nil:
        port = tonumber(port_env)
    end

    let ok = cmd_connect(host, port)
    if ok:
        # Drop straight into the interactive shell with the live relay session.
        run_client_shell()
    end
end


# =========================================
# Query connected devices from an SMP relay (real TCP)
# =========================================
# Mirrors the dashboard's device-management visibility: opens a real TCP
# connection and asks the relay for the list of currently connected devices.
# The relay returns each device's id, platform, info, services, and last_seen.

proc run_devices_query(host, port):
    print("=== SMP Devices (Real TCP) ===")
    print("Querying " + host + ":" + str(port) + " ...")

    let fd = tcp.connect(host, port)
    if fd == -1:
        print("[ERROR] Cannot connect to " + host + ":" + str(port))
        return
    end

    let msg = {
        "op": "list",
        "client_id": 0,
        "platform": "SageSMP",
        "info": "device query",
        "timestamp": clock()
    }
    tcp.sendall(fd, json_encode(msg))

    let raw = tcp.recv(fd, 4096)
    if raw != nil and len(raw) > 0:
        let resp = json_decode(raw)
        if resp != nil and resp["devices"] != nil:
            let devs = resp["devices"]
            print("[OK] " + str(len(devs)) + " device(s) connected to " + host + ":" + str(port))
            if len(devs) == 0:
                print("  (no devices registered)")
            else:
                print("")
                print("  idx  id   platform   last_seen        info")
                print("  ───  ───  ─────────  ───────────────  ───────────────────────────────")
                for i in range(len(devs)):
                    let d = devs[i]
                    let id_s = str(d["id"])
                    let plat = str(d["platform"])
                    let ls = str(d["last_seen"])
                    let info = ""
                    if d["info"] != nil:
                        info = str(d["info"])
                    end
                    print("  " + str(i) + "    " + id_s + "   " + plat + "   " + ls + "   " + info)
                end
            end
        elif resp != nil:
            print("[OK] Connected, but no device list returned.")
            if resp["status"] != nil:
                print("  status: " + str(resp["status"]))
            end
        else:
            print("[WARN] Bad JSON response: " + raw)
        end
    else:
        print("[WARN] No response from " + host + ":" + str(port))
    end

    tcp.close(fd)
    print("[DONE] Disconnected.")
end


proc run_devices_query_mode(mode_idx):
    let argv = sys.args()
    let host = "127.0.0.1"
    let port = 42000
    if len(argv) >= mode_idx + 3:
        host = argv[mode_idx + 1]
        port = tonumber(argv[mode_idx + 2])
    end
    let env_h = sys.getenv("SMP_HOST")
    if env_h != nil:
        host = env_h
    end
    let env_p = sys.getenv("SMP_PORT")
    if env_p != nil:
        port = tonumber(env_p)
    end
    if port == nil or port < 1 or port > 65535:
        print("Error: port must be 1-65535")
        return
    end
    run_devices_query(host, port)
end


# =========================================
# src/sage/client/rpi2_client.sage
# =========================================


let ORANGEPI_HOST = "192.168.254.44"
let ORANGEPI_PORT = 42000
let CLIENT_ID = 1
let HEARTBEAT_INTERVAL = 60


proc rpi2_read_sys_file(path):
    if not io.exists(path):
        return nil
    return io.readfile(path)

proc rpi2_stripnl(s):
    return replace(replace(s, chr(10), ""), chr(13), "")

proc rpi2_get_cpu_temp():
    let raw = rpi2_read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if raw != nil:
        let cleaned = rpi2_stripnl(raw)
        let millideg = tonumber(cleaned)
        if millideg != nil:
            return millideg / 1000.0
        end
    end
    return 45.0 + (clock() % 5)

proc rpi2_get_cpu_load():
    let raw = rpi2_read_sys_file("/proc/loadavg")
    if raw != nil:
        let parts = []
        let cur = ""
        for i in range(len(raw)):
            if raw[i] == " ":
                push(parts, cur)
                cur = ""
            else:
                cur = cur + raw[i]
        if len(cur) > 0:
            push(parts, cur)
        if len(parts) >= 1:
            let load = tonumber(parts[0])
            if load != nil:
                return load
            end
        end
    end
    return 0.4 + (clock() % 10) / 100.0

proc rpi2_get_memory_info():
    let raw = rpi2_read_sys_file("/proc/meminfo")
    if raw != nil:
        let lines = []
        let cur = ""
        for i in range(len(raw)):
            if raw[i] == chr(10):
                push(lines, cur)
                cur = ""
            else:
                cur = cur + raw[i]
        if len(cur) > 0:
            push(lines, cur)
        if len(lines) >= 2:
            let mem_avail = lines[1]
            let parts = []
            cur = ""
            for i in range(len(mem_avail)):
                if mem_avail[i] == " ":
                    if len(cur) > 0:
                        push(parts, cur)
                    cur = ""
                else:
                    cur = cur + mem_avail[i]
            if len(cur) > 0:
                push(parts, cur)
            if len(parts) >= 2:
                return "Available: " + parts[1] + "kB"
            end
        end
    end
    return "Available: 768MB"

proc get_pihole_info():
    let raw = io.readfile("/tmp/sagesmp_pihole.json")
    if raw == nil:
        return nil
    end
    let cleaned = replace(replace(raw, chr(10), ""), chr(13), "")
    return json_decode(cleaned)

proc rpi2_parse_mem_line(line):
    let parts = []
    let cur = ""
    for i in range(len(line)):
        let c = line[i]
        if c == " " or c == ":" or c == chr(9):
            if len(cur) > 0:
                push(parts, cur)
            end
            cur = ""
        else:
            cur = cur + c
        end
    end
    if len(cur) > 0:
        push(parts, cur)
    end
    if len(parts) >= 2:
        return tonumber(parts[1])
    end
    return nil
end

proc rpi2_get_dynamic_telemetry():
    let telem = {}
    
    # 1. CPU Temp
    let temp_raw = rpi2_read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if temp_raw != nil:
        let temp_num = tonumber(rpi2_stripnl(temp_raw))
        if temp_num != nil:
            telem["cpu_temp"] = temp_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_temp"):
        telem["cpu_temp"] = 42.0
    end
    
    # 2. CPU Load
    let load_raw = rpi2_read_sys_file("/proc/loadavg")
    if load_raw != nil:
        let parts = []
        let cur = ""
        for i in range(len(load_raw)):
            if load_raw[i] == " ":
                if len(cur) > 0:
                    push(parts, cur)
                end
                cur = ""
            else:
                cur = cur + load_raw[i]
            end
        end
        if len(parts) >= 1:
            let load_val = tonumber(parts[0])
            if load_val != nil:
                telem["cpu_load"] = load_val
            end
        end
    end
    if not dict_has(telem, "cpu_load"):
        telem["cpu_load"] = 0.25
    end
    
    # 3. CPU Freq
    let freq_raw = rpi2_read_sys_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
    if freq_raw != nil:
        let freq_num = tonumber(rpi2_stripnl(freq_raw))
        if freq_num != nil:
            telem["cpu_mhz"] = freq_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_mhz"):
        telem["cpu_mhz"] = 800.0
    end
    
    # 4. RAM details
    let mem_raw = rpi2_read_sys_file("/proc/meminfo")
    if mem_raw != nil:
        let lines = []
        let cur = ""
        for i in range(len(mem_raw)):
            let c = mem_raw[i]
            if c == chr(10):
                push(lines, cur)
                cur = ""
            else:
                cur = cur + c
            end
        end
        if len(cur) > 0:
            push(lines, cur)
        end
        
        let total_kb = nil
        let avail_kb = nil
        for i in range(len(lines)):
            let line = lines[i]
            if len(line) >= 8 and substring(line, 0, 8) == "MemTotal":
                total_kb = rpi2_parse_mem_line(line)
            elif len(line) >= 12 and substring(line, 0, 12) == "MemAvailable":
                avail_kb = rpi2_parse_mem_line(line)
            end
        end
        
        if total_kb != nil:
            telem["ram_total_mb"] = total_kb / 1024.0
        end
        if avail_kb != nil:
            telem["ram_avail_mb"] = avail_kb / 1024.0
        end
    end
    if not dict_has(telem, "ram_total_mb"):
        telem["ram_total_mb"] = 1024.0
    end
    if not dict_has(telem, "ram_avail_mb"):
        telem["ram_avail_mb"] = 768.0
    end
    
    return telem
end

proc get_rpi2_info():
    let telem = rpi2_get_dynamic_telemetry()
    return "Temp: " + str(telem["cpu_temp"]) + "C, Load: " + str(telem["cpu_load"]) + ", Available: " + str(telem["ram_avail_mb"]) + "MB, CpuFreq: " + str(telem["cpu_mhz"]) + "MHz, TotalRam: " + str(telem["ram_total_mb"]) + "MB"

proc rpi2_send_heartbeat():
    let host = ORANGEPI_HOST
    let host_override = sys.getenv("SMP_HOST")
    if host_override != nil:
        host = host_override
    end
    let port = ORANGEPI_PORT
    let port_str = sys.getenv("SMP_PORT")
    if port_str != nil:
        port = tonumber(port_str)
    end

    let fd = tcp.connect(host, port)
    if fd == -1:
        print("[ERROR] Cannot connect to OrangePi at " + host + ":" + str(port))
        return
    end

    let info = get_rpi2_info()
    let msg = {"client_id": CLIENT_ID, "platform": "RPi2", "info": info, "timestamp": clock()}
    let pihole = get_pihole_info()
    if pihole != nil:
        msg["services"] = pihole
    end
    tcp.sendall(fd, json_encode(msg))

    let raw = tcp.recv(fd, 4096)
    if raw != nil:
        let resp = json_decode(raw)
        if resp != nil:
            print("[HEARTBEAT OK] nodes=" + str(resp["node_count"]) + " ts=" + str(resp["server_ts"]))
        else:
            print("[WARN] Bad response: " + raw)
        end
    else:
        print("[WARN] No response from OrangePi")
    end

    tcp.close(fd)
end

proc run_rpi2(mode_idx):
    let argv = sys.args()
    if len(argv) >= mode_idx + 2:
        ORANGEPI_HOST = argv[mode_idx + 1]
    end
    if len(argv) >= mode_idx + 3:
        ORANGEPI_PORT = tonumber(argv[mode_idx + 2])
    end
    print("=== RPi2 Client Starting (Real TCP) ===")
    print("Target: " + ORANGEPI_HOST + ":" + str(ORANGEPI_PORT))
    print("Heartbeat interval: " + str(HEARTBEAT_INTERVAL) + "s")
    print("")

    while true:
        rpi2_send_heartbeat()
        thread.sleep(HEARTBEAT_INTERVAL)
    end
end


# =========================================
# src/sage/client/rpi4_client.sage
# =========================================


let ORANGEPI_HOST = "192.168.254.44"
let ORANGEPI_PORT = 42000
let CLIENT_ID = 2
let HEARTBEAT_INTERVAL = 60


proc rpi4_read_sys_file(path):
    if not io.exists(path):
        return nil
    return io.readfile(path)

proc rpi4_stripnl(s):
    return replace(replace(s, chr(10), ""), chr(13), "")

proc rpi4_get_cpu_temp():
    let raw = rpi4_read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if raw != nil:
        let cleaned = rpi4_stripnl(raw)
        let millideg = tonumber(cleaned)
        if millideg != nil:
            return millideg / 1000.0
        end
    end
    return 45.0 + (clock() % 5)

proc rpi4_get_cpu_load():
    let raw = rpi4_read_sys_file("/proc/loadavg")
    if raw != nil:
        let parts = []
        let cur = ""
        for i in range(len(raw)):
            if raw[i] == " ":
                push(parts, cur)
                cur = ""
            else:
                cur = cur + raw[i]
        if len(cur) > 0:
            push(parts, cur)
        if len(parts) >= 1:
            let load = tonumber(parts[0])
            if load != nil:
                return load
            end
        end
    end
    return 0.4 + (clock() % 10) / 100.0

proc rpi4_get_memory_info():
    let raw = rpi4_read_sys_file("/proc/meminfo")
    if raw != nil:
        let lines = []
        let cur = ""
        for i in range(len(raw)):
            if raw[i] == chr(10):
                push(lines, cur)
                cur = ""
            else:
                cur = cur + raw[i]
        if len(cur) > 0:
            push(lines, cur)
        if len(lines) >= 2:
            let mem_avail = lines[1]
            let parts = []
            cur = ""
            for i in range(len(mem_avail)):
                if mem_avail[i] == " ":
                    if len(cur) > 0:
                        push(parts, cur)
                    cur = ""
                else:
                    cur = cur + mem_avail[i]
            if len(cur) > 0:
                push(parts, cur)
            if len(parts) >= 2:
                return "Available: " + parts[1] + "kB"
            end
        end
    end
    return "Available: 768MB"

proc get_gpu_temp():
    let raw = rpi4_read_sys_file("/sys/class/thermal/thermal_zone1/temp")
    if raw != nil:
        let cleaned = rpi4_stripnl(raw)
        let millideg = tonumber(cleaned)
        if millideg != nil:
            return "GPU: " + str(millideg / 1000.0) + "C"
        end
    end
    return "GPU: N/A"

proc get_throttling():
    let raw = rpi4_read_sys_file("/sys/devices/platform/soc/soc:firmware/get_throttled")
    if raw != nil:
        let cleaned = rpi4_stripnl(raw)
        let val = tonumber(cleaned)
        if val != nil and val > 0:
            return "THROTTLED"
        end
    end
    return "OK"

proc get_services_info():
    let raw = io.readfile("/tmp/sagesmp_services.json")
    if raw == nil:
        return nil
    return json_decode(raw)

proc get_compile_info():
    let raw = io.readfile("/tmp/sagesmp_compile_result.json")
    if raw == nil:
        return nil
    return json_decode(raw)

proc rpi4_parse_mem_line(line):
    let parts = []
    let cur = ""
    for i in range(len(line)):
        let c = line[i]
        if c == " " or c == ":" or c == chr(9):
            if len(cur) > 0:
                push(parts, cur)
            end
            cur = ""
        else:
            cur = cur + c
        end
    end
    if len(cur) > 0:
        push(parts, cur)
    end
    if len(parts) >= 2:
        return tonumber(parts[1])
    end
    return nil
end

proc rpi4_get_dynamic_telemetry():
    let telem = {}
    
    # 1. CPU Temp
    let temp_raw = rpi4_read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if temp_raw != nil:
        let temp_num = tonumber(rpi4_stripnl(temp_raw))
        if temp_num != nil:
            telem["cpu_temp"] = temp_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_temp"):
        telem["cpu_temp"] = 42.0
    end
    
    # 2. CPU Load
    let load_raw = rpi4_read_sys_file("/proc/loadavg")
    if load_raw != nil:
        let parts = []
        let cur = ""
        for i in range(len(load_raw)):
            if load_raw[i] == " ":
                if len(cur) > 0:
                    push(parts, cur)
                end
                cur = ""
            else:
                cur = cur + load_raw[i]
            end
        end
        if len(parts) >= 1:
            let load_val = tonumber(parts[0])
            if load_val != nil:
                telem["cpu_load"] = load_val
            end
        end
    end
    if not dict_has(telem, "cpu_load"):
        telem["cpu_load"] = 0.25
    end
    
    # 3. CPU Freq
    let freq_raw = rpi4_read_sys_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
    if freq_raw != nil:
        let freq_num = tonumber(rpi4_stripnl(freq_raw))
        if freq_num != nil:
            telem["cpu_mhz"] = freq_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_mhz"):
        telem["cpu_mhz"] = 1500.0
    end
    
    # 4. RAM details
    let mem_raw = rpi4_read_sys_file("/proc/meminfo")
    if mem_raw != nil:
        let lines = []
        let cur = ""
        for i in range(len(mem_raw)):
            let c = mem_raw[i]
            if c == chr(10):
                push(lines, cur)
                cur = ""
            else:
                cur = cur + c
            end
        end
        if len(cur) > 0:
            push(lines, cur)
        end
        
        let total_kb = nil
        let avail_kb = nil
        for i in range(len(lines)):
            let line = lines[i]
            if len(line) >= 8 and substring(line, 0, 8) == "MemTotal":
                total_kb = rpi4_parse_mem_line(line)
            elif len(line) >= 12 and substring(line, 0, 12) == "MemAvailable":
                avail_kb = rpi4_parse_mem_line(line)
            end
        end
        
        if total_kb != nil:
            telem["ram_total_mb"] = total_kb / 1024.0
        end
        if avail_kb != nil:
            telem["ram_avail_mb"] = avail_kb / 1024.0
        end
    end
    if not dict_has(telem, "ram_total_mb"):
        telem["ram_total_mb"] = 2048.0
    end
    if not dict_has(telem, "ram_avail_mb"):
        telem["ram_avail_mb"] = 1536.0
    end
    
    return telem
end

proc get_rpi4_info():
    let telem = rpi4_get_dynamic_telemetry()
    let gpu = get_gpu_temp()
    let throttle = get_throttling()
    return "Temp: " + str(telem["cpu_temp"]) + "C, Load: " + str(telem["cpu_load"]) + ", Available: " + str(telem["ram_avail_mb"]) + "MB, " + gpu + ", " + throttle + ", CpuFreq: " + str(telem["cpu_mhz"]) + "MHz, TotalRam: " + str(telem["ram_total_mb"]) + "MB"

proc rpi4_send_heartbeat():
    let host = ORANGEPI_HOST
    let host_override = sys.getenv("SMP_HOST")
    if host_override != nil:
        host = host_override
    end
    let port = ORANGEPI_PORT
    let port_str = sys.getenv("SMP_PORT")
    if port_str != nil:
        port = tonumber(port_str)
    end

    let fd = tcp.connect(host, port)
    if fd == -1:
        print("[ERROR] Cannot connect to OrangePi at " + host + ":" + str(port))
        return
    end

    let info = get_rpi4_info()
    let msg = {"client_id": CLIENT_ID, "platform": "RPi4", "info": info, "timestamp": clock()}
    let services = get_services_info()
    if services != nil:
        msg["services"] = services
    end
    let compile = get_compile_info()
    if compile != nil:
        msg["compile"] = compile
    end
    tcp.sendall(fd, json_encode(msg))

    let raw = tcp.recv(fd, 4096)
    if raw != nil:
        let resp = json_decode(raw)
        if resp != nil:
            print("[HEARTBEAT OK] nodes=" + str(resp["node_count"]) + " ts=" + str(resp["server_ts"]))
        else:
            print("[WARN] Bad response: " + raw)
        end
    else:
        print("[WARN] No response from OrangePi")
    end

    tcp.close(fd)
end

proc run_rpi4(mode_idx):
    let argv = sys.args()
    if len(argv) >= mode_idx + 2:
        ORANGEPI_HOST = argv[mode_idx + 1]
    end
    if len(argv) >= mode_idx + 3:
        ORANGEPI_PORT = tonumber(argv[mode_idx + 2])
    end
    print("=== RPi4 Client Starting (Real TCP) ===")
    print("Target: " + ORANGEPI_HOST + ":" + str(ORANGEPI_PORT))
    print("Heartbeat interval: " + str(HEARTBEAT_INTERVAL) + "s")
    print("")

    while true:
        rpi4_send_heartbeat()
        thread.sleep(HEARTBEAT_INTERVAL)
    end
end


# =========================================
# src/sage/client/smp_client.sage
# =========================================
# SMP Unified Client + Router
# ===========================
# Run as a CLIENT to connect to a router and exchange encrypted messages, or
# run as a ROUTER to accept client connections, assign node IDs, and forward
# messages between clients.
#
# The router uses an RTOS scheduler with three background tasks:
#   - accept_task  : polls the connection queue for new client JOIN requests
#   - message_task : polls per-client mailboxes and routes pending messages
#   - heartbeat_task: checks for stale / timed-out clients and removes them
#
# Usage:
#   ./bin/smp_client [--port <port>] [--host <host>]          # client mode
#   ./bin/smp_client --router [--port <port>] [--host <host>] # router mode



# ============================================================================
# Constants
# ============================================================================

let SMP_VERSION      = "1.0.0"
let SMP_OP_HEARTBEAT = 0
let SMP_OP_MESSAGE   = 1
let SMP_OP_JOIN      = 2
let SMP_OP_LEAVE     = 3
let SMP_OP_ASSIGN    = 10
let SMP_OP_FORWARD   = 11

let NODE_STATE_DISCONNECTED = 0
let NODE_STATE_CONNECTED    = 2
let NODE_STATE_READY        = 3

let DEFAULT_HOST      = "127.0.0.1"
let DEFAULT_PORT      = 42000
let DEFAULT_MAX_NODES = 64

# ============================================================================
# RTOS Constants (mirrored from rtos.sage — no import needed)
# ============================================================================

let RTOS_MAX_TASKS    = 16
let RTOS_MAX_PRIORITY = 8
let RTOS_GC_INTERVAL  = 100   # run GC every N ticks

let TASK_READY     = 0
let TASK_RUNNING   = 1
let TASK_SLEEPING  = 2
let TASK_BLOCKED   = 3
let TASK_SUSPENDED = 4

# Task name constants — used to identify tasks in rtos_dispatch_task
let TASK_ACCEPT    = "accept_task"
let TASK_MESSAGE   = "message_task"
let TASK_HEARTBEAT = "heartbeat_task"

# ============================================================================
# RTOS State
# ============================================================================

let rtos_tasks      = []
let rtos_task_count = 0
let rtos_current    = 0
let rtos_tick       = 0
let rtos_gc_ticks   = 0
let rtos_running    = false

# ============================================================================
# RTOS Core
# ============================================================================

proc rtos_init():
    rtos_tasks      = []
    rtos_task_count = 0
    rtos_current    = 0
    rtos_tick       = 0
    rtos_gc_ticks   = 0
    rtos_running    = true
    print("[RTOS] Scheduler initialized (" + str(RTOS_MAX_TASKS) + " slots, " +
          str(RTOS_MAX_PRIORITY) + " priorities)")

proc rtos_task_create(name, priority, period_ticks):
    if rtos_task_count >= RTOS_MAX_TASKS:
        print("[RTOS] Cannot create task '" + name + "': task limit reached")
        return -1
    if priority >= RTOS_MAX_PRIORITY:
        priority = RTOS_MAX_PRIORITY - 1
    let tcb = {
        "name":       name,
        "priority":   priority,
        "period":     period_ticks,   # how many ticks between runs (0 = every tick)
        "state":      TASK_READY,
        "last_run":   0,
        "run_count":  0,
        "sleep_until":0,
        "id":         rtos_task_count
    }
    push(rtos_tasks, tcb)
    rtos_task_count = rtos_task_count + 1
    print("[RTOS] Task created: '" + name + "'  prio=" + str(priority) +
          "  period=" + str(period_ticks) + " ticks  id=" + str(tcb["id"]))
    return tcb["id"]

proc rtos_sleep_task(task_id, ticks):
    if task_id >= 0 and task_id < rtos_task_count:
        rtos_tasks[task_id]["state"]      = TASK_SLEEPING
        rtos_tasks[task_id]["sleep_until"]= rtos_tick + ticks

proc rtos_suspend_task(task_id):
    if task_id >= 0 and task_id < rtos_task_count:
        rtos_tasks[task_id]["state"] = TASK_SUSPENDED

proc rtos_resume_task(task_id):
    if task_id >= 0 and task_id < rtos_task_count:
        if rtos_tasks[task_id]["state"] == TASK_SUSPENDED:
            rtos_tasks[task_id]["state"] = TASK_READY

proc rtos_halt():
    rtos_running = false
    print("[RTOS] Scheduler halted at tick " + str(rtos_tick))

proc rtos_print_tasks():
    let state_names = ["READY", "RUNNING", "SLEEPING", "BLOCKED", "SUSPENDED"]
    print("[RTOS] Task list (tick=" + str(rtos_tick) + "):")
    for i in range(rtos_task_count):
        let t = rtos_tasks[i]
        let sn = state_names[t["state"]]
        print("  [" + str(t["id"]) + "] " + t["name"] +
              "  state=" + sn +
              "  prio="  + str(t["priority"]) +
              "  runs="  + str(t["run_count"]) +
              "  period="+ str(t["period"]))

# ============================================================================
# OTP Crypto  (runs automatically — user never calls these directly)
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
        push(key, (h % 127) - 63)
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
    return {
        "payload": encrypted,
        "otp":     key,
        "sig":     sig,
        "key_len": len(str(message)),
        "from":    sender_id,
        "to":      recipient_id
    }

proc crypto_open(envelope, secret_key, otp_pass, otp_seed, expected_sender):
    if envelope["sig"] == nil or len(envelope["sig"]) < 2:
        return nil
    if not _verify_sig(envelope["payload"], envelope["sig"], secret_key, expected_sender):
        return nil
    let key_len = envelope["key_len"]
    let key = _generate_otp_key(otp_pass, key_len, otp_seed)
    return _otp_decrypt(envelope["payload"], key)

# ============================================================================
# Router State + Mailbox-based message queues
# ============================================================================

let router_state = {
    "enabled":         false,
    "host":            "0.0.0.0",
    "port":            DEFAULT_PORT,
    "clients":         {},    # str(node_id) -> client record
    "next_id":         1,
    "route_log":       [],
    "heartbeat_ticks": 0,
    "client_timeout":  30     # ticks before a silent client is dropped
}

# Per-client mailboxes: str(node_id) -> mailbox queue (list of pending msgs)
let router_mailboxes = {}

# Connection queue: simulates the OS accept() buffer — new JOIN requests land here
# Each entry: {host, port, name, op}
let router_conn_queue = []

# ============================================================================
# Mailbox helpers (lightweight — no import needed)
# ============================================================================

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

# ============================================================================
# Router — core registration / routing
# ============================================================================

proc router_register(host, port, name):
    let id = router_state["next_id"]
    router_state["next_id"] = router_state["next_id"] + 1
    let client = {
        "id":         id,
        "host":       host,
        "port":       port,
        "name":       name,
        "connected":  true,
        "last_seen":  rtos_tick,
        "msg_count":  0
    }
    router_state["clients"][str(id)] = client
    # Create a dedicated mailbox for this client
    router_mailboxes[str(id)] = mb_create(id)
    print("[Router] Registered node-" + str(id) + " \"" + name + "\" @ " + host + ":" + str(port))
    return id

proc router_unregister(node_id):
    let key = str(node_id)
    if dict_has(router_state["clients"], key):
        let c = router_state["clients"][key]
        c["connected"] = false
        if dict_has(router_mailboxes, key):
            dict_delete(router_mailboxes, key)
        dict_delete(router_state["clients"], key)
        print("[Router] Removed node-" + str(node_id) + " \"" + c["name"] + "\"")
        return true
    return false

proc router_route(src_id, dst_id, payload, sig, key_len):
    let key = str(dst_id)
    if not dict_has(router_state["clients"], key):
        print("[Router] Route FAILED: node-" + str(dst_id) + " not registered")
        return false
    let dst = router_state["clients"][key]
    if not dst["connected"]:
        print("[Router] Route FAILED: node-" + str(dst_id) + " offline")
        return false
    let mb = router_mailboxes[key]
    let sig_val = sig
    let key_len_val = key_len
    if sig_val == nil:
        sig_val = []
    if key_len_val == nil:
        key_len_val = len(str(payload))
    mb_send(mb, {"from": src_id, "to": dst_id, "payload": payload, "sig": sig_val, "key_len": key_len_val, "ts": rtos_tick})
    dst["msg_count"] = dst["msg_count"] + 1
    push(router_state["route_log"], {
        "from": src_id, "to": dst_id,
        "payload_len": len(str(payload)), "tick": rtos_tick
    })
    print("[Router] Routed  node-" + str(src_id) + " -> node-" + str(dst_id) +
          "  (" + str(len(str(payload))) + " bytes)")
    return true

# ============================================================================
# RTOS Task Bodies
# (Sage cannot store proc references, so we dispatch by task name string)
# ============================================================================

# --- accept_task ---
# Polls router_conn_queue for pending JOIN requests and registers each client.
proc task_body_accept():
    if len(router_conn_queue) == 0:
        return
    let req = router_conn_queue[0]
    # Dequeue
    let new_q = []
    for i in range(len(router_conn_queue) - 1):
        push(new_q, router_conn_queue[i + 1])
    router_conn_queue = new_q

    if req["op"] == SMP_OP_JOIN:
        let assigned_id = router_register(req["host"], req["port"], req["name"])
        print("[accept_task] JOIN from \"" + req["name"] + "\" -> assigned node-" + str(assigned_id))
    elif req["op"] == SMP_OP_LEAVE:
        router_unregister(req["node_id"])
        print("[accept_task] LEAVE from node-" + str(req["node_id"]))

# --- message_task ---
# Drains every client's mailbox and prints delivered messages.
# In a real network stack this would write back over the socket.
proc task_body_message():
    let ids = dict_keys(router_mailboxes)
    let total = 0
    for i in range(len(ids)):
        let mb  = router_mailboxes[ids[i]]
        let pending = mb_pending(mb)
        if pending > 0:
            let msg = mb_recv(mb)
            while msg != nil:
                print("[message_task] Delivering  node-" + str(msg["from"]) +
                      " -> node-" + str(msg["to"]) + "  payload=" + str(msg["payload"]))
                total = total + 1
                msg = mb_recv(mb)
    if total > 0:
        print("[message_task] Delivered " + str(total) + " message(s) this tick")

# --- heartbeat_task ---
# Increments heartbeat counter, checks for timed-out clients, and triggers GC.
proc task_body_heartbeat():
    router_state["heartbeat_ticks"] = router_state["heartbeat_ticks"] + 1
    let timeout = router_state["client_timeout"]
    let ids = dict_keys(router_state["clients"])
    let dropped = 0
    for i in range(len(ids)):
        let c = router_state["clients"][ids[i]]
        if c["connected"]:
            let idle = rtos_tick - c["last_seen"]
            if idle > timeout:
                print("[heartbeat_task] node-" + str(c["id"]) +
                      " timed out (idle=" + str(idle) + " ticks) — removing")
                router_unregister(c["id"])
                dropped = dropped + 1

    # Periodic GC
    if rtos_gc_ticks >= RTOS_GC_INTERVAL:
        gc_collect()
        rtos_gc_ticks = 0
        print("[heartbeat_task] GC collected at tick " + str(rtos_tick))

    let client_count = len(dict_keys(router_state["clients"]))
    print("[heartbeat_task] tick=" + str(rtos_tick) + "  clients=" + str(client_count) + "  hb#" + str(router_state["heartbeat_ticks"]))

# ============================================================================
# RTOS Dispatcher — called each tick for every ready task
# (replaces first-class proc references, which Sage does not support)
# ============================================================================

proc rtos_dispatch_task(name):
    if name == TASK_ACCEPT:
        task_body_accept()
    elif name == TASK_MESSAGE:
        task_body_message()
    elif name == TASK_HEARTBEAT:
        task_body_heartbeat()

# ============================================================================
# RTOS Scheduler Loop
# Runs one tick: wakes sleeping tasks, then executes all READY tasks in
# priority order.  Shell input is interleaved between ticks so the router
# stays interactive while the background tasks run.
# ============================================================================

proc rtos_tick_once():
    rtos_tick     = rtos_tick + 1
    rtos_gc_ticks = rtos_gc_ticks + 1

    # Wake sleeping tasks whose timer has expired
    for i in range(rtos_task_count):
        let t = rtos_tasks[i]
        if t["state"] == TASK_SLEEPING and rtos_tick >= t["sleep_until"]:
            t["state"] = TASK_READY

    # Execute all READY tasks in priority order (highest first)
    let prio = RTOS_MAX_PRIORITY - 1
    while prio >= 0:
        for i in range(rtos_task_count):
            let t = rtos_tasks[i]
            if t["state"] == TASK_READY and t["priority"] == prio:
                # Honour period — only run if enough ticks have elapsed
                let due = false
                if t["period"] == 0:
                    due = true
                elif (rtos_tick - t["last_run"]) >= t["period"]:
                    due = true
                if due:
                    t["state"]    = TASK_RUNNING
                    t["last_run"] = rtos_tick
                    t["run_count"]= t["run_count"] + 1
                    rtos_dispatch_task(t["name"])
                    if t["state"] == TASK_RUNNING:
                        t["state"] = TASK_READY
        prio = prio - 1

# ============================================================================
# Client Session State
# ============================================================================

let session = {
    "connected":   false,
    "router_host": "",
    "router_port": 0,
    "my_id":       0,
    "my_name":     "smp-client",
    "secret_key":  "change_this_key",
    "otp_pass":    "change_this_passphrase",
    "otp_seed":    12345,
    "inbox":       [],
    "outbox":      [],
    "msg_log":     [],
    "seq":         0,
    "live_fd":     0
}

# ============================================================================
# Client — Connection (router assigns node ID automatically on connect)
# ============================================================================

proc cmd_connect(host, port):
    if session["connected"]:
        print("[SMP] Already connected to " + session["router_host"] + ":" +
              str(session["router_port"]) + "  (disconnect first)")
        return false
    end

    # Open a real TCP connection to the SMP relay and perform a heartbeat
    # handshake so we can drop straight into the interactive shell.
    print("[SMP] Connecting to " + host + ":" + str(port) + " ...")
    let fd = tcp.connect(host, port)
    if fd == -1:
        print("[SMP] Connection failed to " + host + ":" + str(port))
        return false
    end

    let hb = {
        "client_id": 0,
        "platform": "SageSMP",
        "info": "interactive client",
        "timestamp": clock()
    }
    tcp.sendall(fd, json_encode(hb))
    let raw = tcp.recv(fd, 4096)
    let node_count = 0
    if raw != nil and len(raw) > 0:
        let resp = json_decode(raw)
        if resp != nil and resp["node_count"] != nil:
            node_count = tonumber(resp["node_count"])
        end
    end
    # Relay waits for the client to close first; for an interactive session we
    # keep our side open, so close this handshake socket and reconnect lazily.
    tcp.close(fd)

    session["router_host"] = host
    session["router_port"] = port
    session["connected"]   = true
    session["my_id"]       = node_count + 1
    session["live_fd"]     = 0
    print("[SMP] Connected to relay at " + host + ":" + str(port) +
          "  (cluster node_count=" + str(node_count) + ")")
    print("[SMP] Entering interactive shell. Type 'help' for commands, 'disconnect' to leave.")
    return true

proc cmd_disconnect():
    if not session["connected"]:
        print("[SMP] Not connected.")
        return false
    let old_id = session["my_id"]
    if session["live_fd"] != 0 and session["live_fd"] != -1:
        tcp.close(session["live_fd"])
    end
    session["connected"]   = false
    session["my_id"]       = 0
    session["router_host"] = ""
    session["router_port"] = 0
    session["live_fd"]     = 0
    print("[SMP] Disconnected from relay. Node ID " + str(old_id) + " released.")
    return true

# ============================================================================
# Client — Send / Receive
# ============================================================================

proc cmd_send(target_id, message):
    if not session["connected"]:
        print("[SMP] Not connected. Use: connect <router_host> <port>")
        return false
    if session["my_id"] == 0:
        print("[SMP] No node ID assigned yet.")
        return false

    let envelope = crypto_seal(
        message,
        session["secret_key"],
        session["otp_pass"],
        session["otp_seed"],
        session["my_id"],
        target_id
    )

    session["seq"] = session["seq"] + 1
    push(session["outbox"], {
        "seq":     session["seq"],
        "to":      target_id,
        "text":    message,
        "payload": envelope["payload"],
        "ts":      0
    })
    push(session["msg_log"], {"dir": "OUT", "to": target_id, "text": message, "ts": 0})

    router_route(session["my_id"], target_id, envelope["payload"], envelope["sig"], envelope["key_len"])
    print("[OUT -> node-" + str(target_id) + "] " + message +
          "  (seq=" + str(session["seq"]) + ")")
    return true

proc cmd_broadcast(message):
    if not session["connected"]:
        print("[SMP] Not connected.")
        return false
    push(session["msg_log"], {"dir": "BCAST", "to": 0, "text": message, "ts": 0})
    let ids = dict_keys(router_state["clients"])
    let sent = 0
    for i in range(len(ids)):
        let c = router_state["clients"][ids[i]]
        if c["connected"] and c["id"] != session["my_id"]:
            let envelope = crypto_seal(
                message,
                session["secret_key"],
                session["otp_pass"],
                session["otp_seed"],
                session["my_id"],
                c["id"]
            )
            router_route(session["my_id"], c["id"], envelope["payload"], envelope["sig"], envelope["key_len"])
            sent = sent + 1
    print("[BCAST] Routed to " + str(sent) + " peer(s)")
    return true

proc cmd_recv_simulate(sender_id, encrypted_payload):
    let envelope = {
        "payload": encrypted_payload,
        "sig":     _sign(encrypted_payload, session["secret_key"], sender_id),
        "from":    sender_id,
        "to":      session["my_id"]
    }
    let plaintext = crypto_open(
        envelope,
        session["secret_key"],
        session["otp_pass"],
        session["otp_seed"],
        sender_id
    )
    if plaintext == nil:
        print("[SMP] Bad signature from node-" + str(sender_id))
        return nil
    let entry = {"dir": "IN", "from": sender_id, "text": plaintext, "ts": 0}
    push(session["inbox"], entry)
    push(session["msg_log"], entry)
    print("[IN  <- node-" + str(sender_id) + "] " + plaintext)
    _auto_relay_check(sender_id, plaintext)
    return plaintext

proc _poll_router_mailbox():
    if session["my_id"] == 0:
        return
    let key = str(session["my_id"])
    if not dict_has(router_mailboxes, key):
        return
    let mb = router_mailboxes[key]
    let msg = mb_recv(mb)
    while msg != nil:
        let payload = msg["payload"]
        let key_len_val = msg["key_len"]
        if key_len_val == nil:
            key_len_val = len(str(payload))
        if dict_has(msg, "sig") and len(msg["sig"]) >= 2:
            let envelope = {
                "payload": payload,
                "sig":     msg["sig"],
                "key_len": key_len_val,
                "from":    msg["from"],
                "to":      session["my_id"]
            }
            let plaintext = crypto_open(
                envelope,
                session["secret_key"],
                session["otp_pass"],
                session["otp_seed"],
                msg["from"]
            )
            if plaintext != nil:
                push(session["inbox"], {"dir": "IN", "from": msg["from"], "text": plaintext, "ts": msg["ts"]})
                push(session["msg_log"], {"dir": "IN", "from": msg["from"], "text": plaintext, "ts": msg["ts"]})
                print("[IN  <- node-" + str(msg["from"]) + "] " + plaintext)
                _auto_relay_check(msg["from"], plaintext)
        else:
            let key_gen = _generate_otp_key(session["otp_pass"], key_len_val, session["otp_seed"])
            let plaintext = _otp_decrypt(payload, key_gen)
            push(session["inbox"], {"dir": "IN", "from": msg["from"], "text": plaintext, "ts": msg["ts"]})
            push(session["msg_log"], {"dir": "IN", "from": msg["from"], "text": plaintext, "ts": msg["ts"]})
            print("[IN  <- node-" + str(msg["from"]) + "] " + plaintext)
            _auto_relay_check(msg["from"], plaintext)
        msg = mb_recv(mb)

# ============================================================================
# Client — Inbox / Outbox / Log
# ============================================================================

proc cmd_inbox():
    if len(session["inbox"]) == 0:
        print("  (inbox empty)")
        return
    for i in range(len(session["inbox"])):
        let m = session["inbox"][i]
        print("  [" + str(i) + "] FROM node-" + str(m["from"]) + ": " + m["text"])

proc cmd_outbox():
    if len(session["outbox"]) == 0:
        print("  (outbox empty)")
        return
    for i in range(len(session["outbox"])):
        let m = session["outbox"][i]
        print("  [" + str(i) + "] TO node-" + str(m["to"]) +
              "  seq=" + str(m["seq"]) + "  \"" + m["text"] + "\"")

proc cmd_log():
    if len(session["msg_log"]) == 0:
        print("  (no messages)")
        return
    for i in range(len(session["msg_log"])):
        let m = session["msg_log"][i]
        if m["dir"] == "IN":
            print("  [" + str(i) + "] <- node-" + str(m["from"]) + " | " + m["text"])
        elif m["dir"] == "BCAST":
            print("  [" + str(i) + "] >> BCAST | " + m["text"])
        else:
            print("  [" + str(i) + "] -> node-" + str(m["to"]) + " | " + m["text"])

# ============================================================================
# Client — Crypto config
# ============================================================================

proc cmd_set_secret(key):
    session["secret_key"] = key
    print("[SMP] Secret key updated.")

proc cmd_set_otp_pass(pass):
    session["otp_pass"] = pass
    print("[SMP] OTP passphrase updated.")

proc cmd_set_otp_seed(seed):
    session["otp_seed"] = tonumber(seed)
    print("[SMP] OTP seed set to " + str(session["otp_seed"]))

proc cmd_show_crypto():
    print("  secret_key : " + session["secret_key"])
    print("  otp_pass   : " + session["otp_pass"])
    print("  otp_seed   : " + str(session["otp_seed"]))
    print("  my_id      : " + str(session["my_id"]) + "  (assigned by router)")

# ============================================================================
# Auto-Relay Rules
# ============================================================================

let relay_rules   = []
let relay_enabled = true

proc cmd_relay_on():
    relay_enabled = true
    print("[Relay] Auto-relay ENABLED.")

proc cmd_relay_off():
    relay_enabled = false
    print("[Relay] Auto-relay DISABLED.")

proc cmd_add_sender_rule(sender_id, reply_msg):
    let rule = {
        "type":      "sender",
        "trigger":   tonumber(sender_id),
        "reply_msg": reply_msg,
        "target_id": tonumber(sender_id)
    }
    push(relay_rules, rule)
    let idx = len(relay_rules) - 1
    print("[Relay] Rule [" + str(idx) + "] SENDER  from=node-" + str(sender_id) +
          " -> reply=\"" + reply_msg + "\"")
    return idx

proc cmd_add_content_rule(trigger_text, reply_msg):
    let rule = {
        "type":      "content",
        "trigger":   trigger_text,
        "reply_msg": reply_msg,
        "target_id": -1
    }
    push(relay_rules, rule)
    let idx = len(relay_rules) - 1
    print("[Relay] Rule [" + str(idx) + "] CONTENT msg=\"" + trigger_text +
          "\" -> reply=\"" + reply_msg + "\"")
    return idx

proc cmd_remove_rule(idx):
    let i = tonumber(idx)
    if i < 0 or i >= len(relay_rules):
        print("[Relay] No rule at index " + str(i))
        return false
    relay_rules[i]["type"] = "deleted"
    print("[Relay] Rule [" + str(i) + "] removed.")
    return true

proc cmd_list_rules():
    if len(relay_rules) == 0:
        print("  (no relay rules)")
        return
    for i in range(len(relay_rules)):
        let r = relay_rules[i]
        if r["type"] == "deleted":
            print("  [" + str(i) + "] <deleted>")
        elif r["type"] == "sender":
            print("  [" + str(i) + "] SENDER   trigger=node-" + str(r["trigger"]) +
                  "  reply=\"" + r["reply_msg"] + "\"")
        elif r["type"] == "content":
            print("  [" + str(i) + "] CONTENT  trigger=\"" + r["trigger"] +
                  "\"  reply=\"" + r["reply_msg"] + "\"")

proc _auto_relay_check(sender_id, plaintext):
    if not relay_enabled:
        return
    for i in range(len(relay_rules)):
        let r = relay_rules[i]
        if r["type"] == "deleted":
            let skip = true
        elif r["type"] == "sender":
            if r["trigger"] == sender_id:
                print("[Relay] Rule [" + str(i) + "] matched sender node-" +
                      str(sender_id) + " -> auto-reply: \"" + r["reply_msg"] + "\"")
                cmd_send(r["target_id"], r["reply_msg"])
        elif r["type"] == "content":
            if plaintext == r["trigger"]:
                let reply_to = sender_id
                if r["target_id"] != -1:
                    reply_to = r["target_id"]
                print("[Relay] Rule [" + str(i) + "] matched content \"" +
                      r["trigger"] + "\" -> auto-reply: \"" + r["reply_msg"] + "\"")
                cmd_send(reply_to, r["reply_msg"])

# ============================================================================
# Client — Status / Help
# ============================================================================

proc cmd_status():
    let id_str = str(session["my_id"])
    if session["my_id"] == 0:
        id_str = "(not assigned)"
    let state = "disconnected"
    if session["connected"]:
        state = "connected to router @ " + session["router_host"] + ":" + str(session["router_port"])
    print("  state      : " + state)
    print("  my node ID : " + id_str)
    print("  my_name    : " + session["my_name"])
    print("  inbox      : " + str(len(session["inbox"])) + " message(s)")
    print("  outbox     : " + str(len(session["outbox"])) + " message(s)")
    print("  relay      : " + str(relay_enabled) + "  (" + str(len(relay_rules)) + " rules)")

proc cmd_help():
    print("")
    print("  SMP Client  v" + SMP_VERSION)
    print("  ─────────────────────────────────────────────────────────────────")
    print("  CONNECTION  (node IDs assigned by router on connect)")
    print("    connect <host> <port>          Connect to an SMP router")
    print("    devices [<host> <port>]        List devices connected to an SMP relay")
    print("    disconnect                     Disconnect and release node ID")
    print("")
    print("  MESSAGING  (crypto applied automatically, routed via router)")
    print("    send <node_id> <message>       Send encrypted message to a node")
    print("    broadcast <message>            Send to all connected peers")
    print("    recv <sender_id> <payload>     Simulate router delivering a message")
    print("    inbox                          Show received messages")
    print("    outbox                         Show queued outgoing messages")
    print("    log                            Show full message history")
    print("")
    print("  CRYPTO CONFIG")
    print("    set secret <key>               Set shared secret key")
    print("    set otp_pass <passphrase>      Set OTP passphrase")
    print("    set otp_seed <number>          Set OTP seed")
    print("    crypto                         Show current crypto settings")
    print("")
    print("  AUTO-RELAY  (automatic responses to incoming messages)")
    print("    relay on / off                 Enable / disable auto-relay")
    print("    relay rules                    List configured relay rules")
    print("    relay add sender <id> <reply>  Auto-reply to a specific sender")
    print("    relay add content <msg> <reply>Auto-reply when message matches text")
    print("    relay remove <index>           Delete a relay rule by index")
    print("")
    print("  GENERAL")
    print("    status                         Show session state")
    print("    help                           Show this help")
    print("    quit  / exit                   Exit")
    print("  ─────────────────────────────────────────────────────────────────")
    print("")

# ============================================================================
# Client — Command Dispatcher
# ============================================================================

proc _join_parts(parts, start):
    let msg = ""
    for i in range(start, len(parts)):
        if i > start:
            msg = msg + " "
        msg = msg + parts[i]
    return msg

proc dispatch(parts):
    let cmd = parts[0]

    if cmd == "connect":
        if len(parts) < 3:
            print("Usage: connect <host> <port>")
            return
        cmd_connect(parts[1], tonumber(parts[2]))

    elif cmd == "devices":
        # List devices connected to an SMP relay (real TCP).
        # Usage: devices [<host> <port>]
        let dhost = session["router_host"]
        let dport = session["router_port"]
        if len(parts) >= 3:
            dhost = parts[1]
            dport = tonumber(parts[2])
        end
        let env_h = sys.getenv("SMP_HOST")
        if env_h != nil:
            dhost = env_h
        end
        let env_p = sys.getenv("SMP_PORT")
        if env_p != nil:
            dport = tonumber(env_p)
        end
        if dhost == "" or dhost == nil:
            dhost = DEFAULT_HOST
        end
        if dport == 0 or dport == nil:
            dport = DEFAULT_PORT
        end
        run_devices_query(dhost, dport)

    elif cmd == "disconnect":
        cmd_disconnect()

    elif cmd == "send":
        if len(parts) < 3:
            print("Usage: send <node_id> <message ...>")
            return
        cmd_send(tonumber(parts[1]), _join_parts(parts, 2))

    elif cmd == "broadcast":
        if len(parts) < 2:
            print("Usage: broadcast <message ...>")
            return
        cmd_broadcast(_join_parts(parts, 1))

    elif cmd == "recv":
        if len(parts) < 3:
            print("Usage: recv <sender_id> <encrypted_payload>")
            return
        cmd_recv_simulate(tonumber(parts[1]), parts[2])

    elif cmd == "inbox":
        cmd_inbox()

    elif cmd == "outbox":
        cmd_outbox()

    elif cmd == "log":
        cmd_log()

    elif cmd == "set":
        if len(parts) < 3:
            print("Usage: set <secret|otp_pass|otp_seed> <value>")
            return
        let field = parts[1]
        if field == "secret":
            cmd_set_secret(parts[2])
        elif field == "otp_pass":
            cmd_set_otp_pass(parts[2])
        elif field == "otp_seed":
            cmd_set_otp_seed(parts[2])
        else:
            print("Unknown field: " + field + "  (secret | otp_pass | otp_seed)")

    elif cmd == "crypto":
        cmd_show_crypto()

    elif cmd == "relay":
        if len(parts) < 2:
            print("Usage: relay <on|off|rules|add|remove>")
            return
        let sub = parts[1]
        if sub == "on":
            cmd_relay_on()
        elif sub == "off":
            cmd_relay_off()
        elif sub == "rules":
            cmd_list_rules()
        elif sub == "add":
            if len(parts) < 5:
                print("Usage: relay add <sender|content> <trigger> <reply ...>")
                return
            let kind  = parts[2]
            let reply = _join_parts(parts, 4)
            if kind == "sender":
                cmd_add_sender_rule(parts[3], reply)
            elif kind == "content":
                cmd_add_content_rule(parts[3], reply)
            else:
                print("Unknown rule type: " + kind + "  (sender | content)")
        elif sub == "remove":
            if len(parts) < 3:
                print("Usage: relay remove <index>")
                return
            cmd_remove_rule(parts[2])
        else:
            print("Unknown relay sub-command: " + sub)

    elif cmd == "status":
        cmd_status()

    elif cmd == "help" or cmd == "?":
        cmd_help()

    elif cmd == "quit" or cmd == "exit":
        print("Goodbye.")
        return "QUIT"

    else:
        print("Unknown command: " + cmd + "  (type 'help')")

# ============================================================================
# Router — Shell Commands
# ============================================================================

proc router_cmd_clients():
    let ids = dict_keys(router_state["clients"])
    if len(ids) == 0:
        print("  (no clients registered)")
        return
    print("  node-ID  name                  address               msgs   last_seen")
    print("  ───────  ────────────────────  ────────────────────  ─────  ─────────")
    for i in range(len(ids)):
        let c = router_state["clients"][ids[i]]
        let status = "online"
        if not c["connected"]:
            status = "offline"
        print("  " + str(c["id"]) + "        " + c["name"] +
              "  " + c["host"] + ":" + str(c["port"]) +
              "  " + str(c["msg_count"]) +
              "  tick=" + str(c["last_seen"]) + " (" + status + ")")

proc router_cmd_queue():
    if len(router_conn_queue) == 0:
        print("  (connection queue empty)")
        return
    for i in range(len(router_conn_queue)):
        let r = router_conn_queue[i]
        print("  [" + str(i) + "] op=" + str(r["op"]) + " name=" + r["name"] +
              " @ " + r["host"] + ":" + str(r["port"]))

proc router_cmd_mailboxes():
    let ids = dict_keys(router_mailboxes)
    if len(ids) == 0:
        print("  (no mailboxes)")
        return
    for i in range(len(ids)):
        let mb = router_mailboxes[ids[i]]
        print("  node-" + str(mb["id"]) + "  pending=" + str(mb_pending(mb)) +
              "  sent=" + str(mb["stats"]["sent"]) +
              "  received=" + str(mb["stats"]["received"]))

proc router_cmd_route(src_id, dst_id, payload):
    router_route(tonumber(src_id), tonumber(dst_id), payload)

proc router_cmd_log():
    if len(router_state["route_log"]) == 0:
        print("  (no routed messages)")
        return
    for i in range(len(router_state["route_log"])):
        let e = router_state["route_log"][i]
        print("  [" + str(i) + "] tick=" + str(e["tick"]) +
              "  node-" + str(e["from"]) + " -> node-" + str(e["to"]) +
              "  " + str(e["payload_len"]) + " bytes")

proc router_cmd_tasks():
    rtos_print_tasks()

proc router_cmd_tick():
    rtos_tick_once()
    print("[RTOS] Manual tick " + str(rtos_tick) + " done.")

proc router_cmd_status():
    print("  mode        : ROUTER")
    print("  host        : " + router_state["host"])
    print("  port        : " + str(router_state["port"]))
    print("  clients     : " + str(len(dict_keys(router_state["clients"]))))
    print("  conn queue  : " + str(len(router_conn_queue)) + " pending")
    print("  next_id     : " + str(router_state["next_id"]))
    print("  rtos tick   : " + str(rtos_tick))
    print("  routed msgs : " + str(len(router_state["route_log"])))
    print("  hb count    : " + str(router_state["heartbeat_ticks"]))

proc router_cmd_help():
    print("")
    print("  SMP Router  v" + SMP_VERSION)
    print("  ─────────────────────────────────────────────────────────────────")
    print("  RTOS SCHEDULER  (runs automatically each prompt cycle)")
    print("    tick                           Run one scheduler tick manually")
    print("    tasks                          Show RTOS task list & states")
    print("")
    print("  CLIENT MANAGEMENT  (auto-handled by accept_task)")
    print("    clients                        List registered clients")
    print("    queue                          Show pending connection queue")
    print("    mailboxes                      Show per-client mailbox stats")
    print("")
    print("  ROUTING")
    print("    route <src> <dst> <payload>    Manually route a message")
    print("    log                            Show routing history")
    print("")
    print("  GENERAL")
    print("    status                         Show router & RTOS status")
    print("    help                           Show this help")
    print("    quit  / exit                   Stop the router")
    print("  ─────────────────────────────────────────────────────────────────")
    print("")

# ============================================================================
# Router — Command Dispatcher
# ============================================================================

proc router_dispatch(parts):
    let cmd = parts[0]

    if cmd == "clients":
        router_cmd_clients()

    elif cmd == "queue":
        router_cmd_queue()

    elif cmd == "mailboxes":
        router_cmd_mailboxes()

    elif cmd == "route":
        if len(parts) < 4:
            print("Usage: route <src_id> <dst_id> <payload ...>")
            return
        router_cmd_route(parts[1], parts[2], _join_parts(parts, 3))

    elif cmd == "log":
        router_cmd_log()

    elif cmd == "tasks":
        router_cmd_tasks()

    elif cmd == "tick":
        router_cmd_tick()

    elif cmd == "status":
        router_cmd_status()

    elif cmd == "help" or cmd == "?":
        router_cmd_help()

    elif cmd == "quit" or cmd == "exit":
        rtos_halt()
        print("[Router] Shutting down.")
        return "QUIT"

    else:
        print("Unknown router command: " + cmd + "  (type 'help')")

# ============================================================================
# CLI Argument Parsing
# ============================================================================

let _start_as_router = false

proc parse_args(mode_idx):
    let argv = sys.args()
    let i = mode_idx + 1
    while i < len(argv):
        let arg = argv[i]
        if arg == "--help" or arg == "-h":
            print("Usage: smp_client [--router] [--port <port>] [--host <host>]")
            print("")
            print("  --router           Start in router mode")
            print("  --port <port>      Port  (default: " + str(DEFAULT_PORT) + ")")
            print("  --host <host>      Host  (default: " + DEFAULT_HOST + ")")
            print("  --help             Show this message")
            sys.exit(0)
        elif arg == "--router" or arg == "-r":
            _start_as_router = true
        elif arg == "--port" or arg == "-p":
            i = i + 1
            if i >= len(argv):
                print("Error: --port requires a value")
                sys.exit(1)
            end
            let p = tonumber(argv[i])
            if p == nil or p < 1 or p > 65535:
                print("Error: --port must be 1-65535")
                sys.exit(1)
            end
            session["router_port"] = p
            router_state["port"]   = p
        elif arg == "--host" or arg == "-H":
            i = i + 1
            if i >= len(argv):
                print("Error: --host requires a value")
                sys.exit(1)
            end
            session["router_host"] = argv[i]
            router_state["host"]   = argv[i]
        else:
            print("Warning: unknown argument '" + arg + "'  (try --help)")
        end
        i = i + 1
    end

# ============================================================================
# Shell Entry Points
# ============================================================================

proc run_router_shell():
    print("")
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║       SMP Router  v" + SMP_VERSION + "                  ║")
    print("  ║  RTOS-scheduled routing + auto registration  ║")
    print("  ╚══════════════════════════════════════════════╝")
    print("")
    print("  Listening on " + router_state["host"] + ":" + str(router_state["port"]))
    print("")

    router_state["enabled"] = true

    # Initialise RTOS
    rtos_init()

    # Create background tasks
    #   accept_task    — high priority (7), runs every tick (period=1)
    #   message_task   — medium priority (5), runs every 2 ticks
    #   heartbeat_task — low priority (2),  runs every 10 ticks
    rtos_task_create(TASK_ACCEPT,    7, 1)
    rtos_task_create(TASK_MESSAGE,   5, 2)
    rtos_task_create(TASK_HEARTBEAT, 2, 10)

    print("")
    print("  RTOS tasks registered. The scheduler runs one tick before each")
    print("  prompt, automatically accepting clients and routing messages.")
    print("  Type 'help' for available commands.")
    print("")

    let running = true
    while running:
        # Run one scheduler tick before reading input
        rtos_tick_once()

        let line = input("router[tick=" + str(rtos_tick) + "]> ")
        if line == nil or len(str(line)) == 0:
            let skip = true
        else:
            let parts = split(str(line), " ")
            let clean = []
            for i in range(len(parts)):
                if len(parts[i]) > 0:
                    push(clean, parts[i])
            if len(clean) > 0:
                let result = router_dispatch(clean)
                if result == "QUIT":
                    running = false

proc run_client_shell():
    print("")
    print("  ╔══════════════════════════════════════════════╗")
    print("  ║       SMP Client  v" + SMP_VERSION + "                  ║")
    print("  ║   OTP-encrypted messaging + auto-relay       ║")
    print("  ╚══════════════════════════════════════════════╝")
    print("")
    if router_state["port"] != 0:
        print("  Default router port : " + str(router_state["port"]))
    end
    print("  Type 'help' for available commands.")
    print("")

    if session["connected"]:
        print("  [LIVE] Connected to relay " + session["router_host"] + ":" +
              str(session["router_port"]) + "  (use 'devices' to list connected nodes)")
        print("")
    end

    # Initialize RTOS for local simulation (so accept_task processes JOINs)
    rtos_init()
    rtos_task_create(TASK_ACCEPT,    7, 1)
    rtos_task_create(TASK_MESSAGE,   5, 2)
    rtos_task_create(TASK_HEARTBEAT, 2, 10)
    print("  [RTOS] Local router tasks initialized for simulation.")
    print("")

    let running = true
    while running:
        # Run one tick before each prompt to process queued JOINs/messages
        rtos_tick_once()
        _poll_router_mailbox()
        let id_label = ""
        if session["connected"]:
            id_label = "[relay " + session["router_host"] + ":" + str(session["router_port"]) + "] "
        elif session["my_id"] != 0:
            id_label = "[node-" + str(session["my_id"]) + "] "
        end
        let line = input("smp " + id_label + "> ")
        if line == nil or len(str(line)) == 0:
            let skip = true
        else:
            let parts = split(str(line), " ")
            let clean = []
            for i in range(len(parts)):
                if len(parts[i]) > 0:
                    push(clean, parts[i])
            if len(clean) > 0:
                let result = dispatch(clean)
                if result == "QUIT":
                    running = false

# ============================================================================
# Entry Point
# ============================================================================

# 
#     run_router_shell()
# else:
#     run_client_shell()

proc main():
    let argv = sys.args()
    let mode_idx = -1
    for i in range(len(argv)):
        let arg = argv[i]
        if arg != "sage" and arg != "--jit" and arg != "--compile" and not ends_with(arg, ".sage") and not ends_with(arg, "sagesmp"):
            mode_idx = i
            break
        end
    end
    
    if mode_idx == -1:
        print("Usage: sagesmp <relay|pi2|pi4|shell|connect|devices> [args...]")
        print("  sagesmp connect <host> <port>   Connect to an SMP relay server")
        print("  sagesmp devices <host> <port>   List devices on an SMP relay server")
        return
    end
    
    let mode = argv[mode_idx]
    
    if mode == "relay":
        run_orangepi(mode_idx)
    elif mode == "pi2":
        run_rpi2(mode_idx)
    elif mode == "pi4":
        run_rpi4(mode_idx)
    elif mode == "connect":
        run_connect(mode_idx)
    elif mode == "devices":
        run_devices_query_mode(mode_idx)
    elif mode == "shell":
        parse_args(mode_idx)
        if _start_as_router:
            run_router_shell()
        else:
            run_client_shell()
    else:
        print("Unknown mode: " + mode)
    end
end

proc ends_with(s, suffix):
    if len(s) < len(suffix): return false end
    return substring(s, len(s) - len(suffix), len(suffix)) == suffix
end

main()
