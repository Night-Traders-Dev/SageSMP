gc_disable()

import tcp
import thread
import sys
import io

let ORANGEPI_HOST = "192.168.254.44"
let ORANGEPI_PORT = 42000
let CLIENT_ID = 1
let HEARTBEAT_INTERVAL = 60

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

proc read_sys_file(path):
    if not io.exists(path):
        return nil
    return io.readfile(path)

proc stripnl(s):
    return replace(replace(s, chr(10), ""), chr(13), "")

proc get_cpu_temp():
    let raw = read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if raw != nil:
        let cleaned = stripnl(raw)
        let millideg = tonumber(cleaned)
        if millideg != nil:
            return millideg / 1000.0
        end
    end
    return 45.0 + (clock() % 5)

proc get_cpu_load():
    let raw = read_sys_file("/proc/loadavg")
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

proc get_memory_info():
    let raw = read_sys_file("/proc/meminfo")
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
    return json_decode(raw)

proc get_rpi2_info():
    let temp = get_cpu_temp()
    let load = get_cpu_load()
    let mem = get_memory_info()
    return "Temp: " + str(temp) + "C, Load: " + str(load) + ", " + mem

proc send_heartbeat():
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

proc main():
    print("=== RPi2 Client Starting (Real TCP) ===")
    print("Target: " + ORANGEPI_HOST + ":" + str(ORANGEPI_PORT))
    print("Heartbeat interval: " + str(HEARTBEAT_INTERVAL) + "s")
    print("")

    while true:
        send_heartbeat()
        thread.sleep(HEARTBEAT_INTERVAL)
    end
end

main()
