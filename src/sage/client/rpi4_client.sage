gc_disable()

import tcp
import thread
import sys
import io

let argv = sys.args()
let ORANGEPI_HOST = "192.168.254.44"
if len(argv) >= 3:
    ORANGEPI_HOST = argv[2]
end
let ORANGEPI_PORT = 42000
if len(argv) >= 4:
    ORANGEPI_PORT = tonumber(argv[3])
end
let CLIENT_ID = 2
let HEARTBEAT_INTERVAL = 60

import smp.core.smp_json as smp_json

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

proc get_gpu_temp():
    let paths = ["/sys/class/thermal/thermal_zone1/temp", "/sys/class/thermal/thermal_zone0/temp"]
    for i in range(len(paths)):
        let raw = read_sys_file(paths[i])
        if raw != nil:
            let cleaned = stripnl(raw)
            let millideg = tonumber(cleaned)
            if millideg != nil:
                return "GPU: " + str(millideg / 1000.0) + "C"
            end
        end
    end
    return "GPU: N/A"

proc get_throttling():
    let raw = read_sys_file("/sys/devices/platform/soc/soc:firmware/get_throttled")
    if raw != nil:
        let cleaned = stripnl(raw)
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
    return smp_json.json_decode(raw)

proc get_compile_info():
    let raw = io.readfile("/tmp/sagesmp_compile_result.json")
    if raw == nil:
        return nil
    return smp_json.json_decode(raw)

proc parse_mem_line(line):
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

proc get_dynamic_telemetry():
    let telem = {}
    
    # 1. CPU Temp
    let temp_raw = read_sys_file("/sys/class/thermal/thermal_zone0/temp")
    if temp_raw != nil:
        let temp_num = tonumber(stripnl(temp_raw))
        if temp_num != nil:
            telem["cpu_temp"] = temp_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_temp"):
        telem["cpu_temp"] = 42.0
    end
    
    # 2. CPU Load
    let load_raw = read_sys_file("/proc/loadavg")
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
    let freq_raw = read_sys_file("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
    if freq_raw != nil:
        let freq_num = tonumber(stripnl(freq_raw))
        if freq_num != nil:
            telem["cpu_mhz"] = freq_num / 1000.0
        end
    end
    if not dict_has(telem, "cpu_mhz"):
        telem["cpu_mhz"] = 1500.0
    end
    
    # 4. RAM details
    let mem_raw = read_sys_file("/proc/meminfo")
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
                total_kb = parse_mem_line(line)
            elif len(line) >= 12 and substring(line, 0, 12) == "MemAvailable":
                avail_kb = parse_mem_line(line)
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
    let telem = get_dynamic_telemetry()
    let gpu = get_gpu_temp()
    let throttle = get_throttling()
    return "Temp: " + str(telem["cpu_temp"]) + "C, Load: " + str(telem["cpu_load"]) + ", Available: " + str(telem["ram_avail_mb"]) + "MB, " + gpu + ", " + throttle + ", CpuFreq: " + str(telem["cpu_mhz"]) + "MHz, TotalRam: " + str(telem["ram_total_mb"]) + "MB"

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
    tcp.sendall(fd, smp_json.json_encode(msg))

    let raw = tcp.recv(fd, 4096)
    if raw != nil:
        let resp = smp_json.json_decode(raw)
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
    print("=== RPi4 Client Starting (Real TCP) ===")
    print("Target: " + ORANGEPI_HOST + ":" + str(ORANGEPI_PORT))
    print("Heartbeat interval: " + str(HEARTBEAT_INTERVAL) + "s")
    print("")

    while true:
        send_heartbeat()
        thread.sleep(HEARTBEAT_INTERVAL)
    end
end

main()
