# SMP Transport Layer
# ===================
# Network transport for SMP communication using socket/tcp

gc_disable()

import tcp

# Transport modes
let TRANSPORT_TCP = 0
let TRANSPORT_UDP = 1
let TRANSPORT_UNIX = 2

# ============================================================================
# Socket Wrapper
# ============================================================================

proc create_socket():
    let sock = {}
    sock["fd"] = -1
    sock["host"] = ""
    sock["port"] = 0
    sock["connected"] = false
    sock["last_error"] = nil
    sock["is_listener"] = false
    return sock

proc connect(sock, host, port):
    sock["host"] = host
    sock["port"] = port
    let fd = tcp.connect(host, port)
    if fd == -1:
        sock["last_error"] = "connection failed"
        sock["connected"] = false
        return false
    end
    sock["fd"] = fd
    sock["connected"] = true
    return true

proc bind(sock, host, port):
    sock["host"] = host
    sock["port"] = port
    return true

proc listen(sock, backlog):
    let fd = tcp.listen(sock["host"], sock["port"], backlog)
    if fd == -1:
        sock["last_error"] = "listen failed"
        sock["connected"] = false
        return false
    end
    sock["fd"] = fd
    sock["is_listener"] = true
    sock["connected"] = true
    return true

proc accept(sock):
    if not sock["connected"] or sock["fd"] == -1:
        return nil
    end
    let client_fd = tcp.accept(sock["fd"])
    if client_fd == -1:
        return nil
    end
    let client = create_socket()
    client["fd"] = client_fd
    client["connected"] = true
    client["host"] = "127.0.0.1" # Placeholder
    client["port"] = 0           # Placeholder
    return client

proc send(sock, data):
    if not sock["connected"] or sock["fd"] == -1:
        sock["last_error"] = "not connected"
        return 0
    end
    let bytes_sent = tcp.send(sock["fd"], str(data))
    if bytes_sent == -1:
        sock["last_error"] = "send failed"
        return 0
    end
    return bytes_sent

proc recv(sock, size):
    if not sock["connected"] or sock["fd"] == -1:
        return nil
    end
    let data = tcp.recv(sock["fd"], size)
    if data == nil:
        sock["connected"] = false
        return nil
    end
    return data

proc close(sock):
    if sock["fd"] != -1:
        tcp.close(sock["fd"])
        sock["fd"] = -1
    end
    sock["connected"] = false

# ============================================================================
# TCP Transport (High-level)
# ============================================================================

proc create_tcp_client(host, port):
    let client = create_socket()
    connect(client, host, port)
    return client

proc create_tcp_server(port):
    let server = create_socket()
    bind(server, "0.0.0.0", port)
    listen(server, 16)
    return server

# ============================================================================
# Message Framing
# ============================================================================

# Frame a message with length prefix
proc frame_message(msg):
    let str_msg = str(msg)
    let len_prefix = str(len(str_msg))
    while len(len_prefix) < 8:
        len_prefix = "0" + len_prefix
    end
    return len_prefix + str_msg

# Parse framed message (returns dict with len and data)
proc parse_frame(buffer):
    let result = {}
    if len(buffer) >= 8:
        let len_str = buffer[0:8]
        let msg_len = tonumber(len_str)
        if len(buffer) >= 8 + msg_len:
            result["ok"] = true
            result["data"] = buffer[8:8 + msg_len]
            result["remaining"] = buffer[8 + msg_len:]
            return result
        end
    end
    result["ok"] = false
    result["remaining"] = buffer
    return result

# ============================================================================
# Buffer Management
# ============================================================================

proc create_buffer(initial_capacity):
    let buf = {}
    buf["data"] = ""
    buf["capacity"] = initial_capacity
    buf["position"] = 0
    return buf

proc write_buffer(buf, data):
    let str_data = str(data)
    if len(buf["data"]) + len(str_data) > buf["capacity"]:
        return false
    end
    buf["data"] = buf["data"] + str_data
    return true

proc read_buffer(buf, size):
    if len(buf["data"]) < size:
        return nil
    end
    let result = buf["data"][buf["position"]:buf["position"] + size]
    buf["position"] = buf["position"] + size
    return result

proc consume_buffer(buf, size):
    if len(buf["data"]) < buf["position"] + size:
        return nil
    end
    let result = buf["data"][buf["position"]:buf["position"] + size]
    buf["position"] = buf["position"] + size
    return result

proc reset_buffer(buf):
    buf["data"] = ""
    buf["position"] = 0

# ============================================================================
# Connection Management
# ============================================================================

proc create_connection(node):
    let conn = {}
    conn["node"] = node
    conn["socket"] = nil
    conn["buffer"] = create_buffer(65536)
    conn["state"] = 0 # NODE_STATE_DISCONNECTED
    conn["last_heartbeat"] = 0
    conn["heartbeat_interval"] = 1.0
    return conn

proc open_connection(conn, host, port):
    conn["socket"] = create_tcp_client(host, port)
    conn["state"] = 2 # NODE_STATE_CONNECTED
    return conn

proc close_connection(conn):
    if conn["socket"] != nil:
        close(conn["socket"])
    end
    conn["state"] = 0 # NODE_STATE_DISCONNECTED

proc send_message(conn, msg):
    if conn["socket"] == nil or not conn["socket"]["connected"]:
        return false
    end
    let framed = frame_message(msg)
    return send(conn["socket"], framed) > 0

proc recv_message(conn):
    if conn["socket"] == nil or not conn["socket"]["connected"]:
        return nil
    end
    return recv(conn["socket"], 4096)

proc ping(conn):
    conn["last_heartbeat"] = clock()

proc should_ping(conn, interval_secs):
    return (clock() - conn["last_heartbeat"]) > interval_secs

# ============================================================================
# Heartbeat Management
# ============================================================================

proc create_heartbeat(interval_secs):
    let hb = {}
    hb["enabled"] = true
    hb["interval"] = interval_secs
    hb["last_sent"] = 0
    hb["last_recv"] = 0
    hb["missed"] = 0
    hb["timeout"] = 5
    return hb

proc update_heartbeat(hb):
    hb["last_recv"] = clock()
    hb["missed"] = 0

proc check_heartbeat(hb):
    if (clock() - hb["last_recv"]) > hb["timeout"]:
        hb["missed"] = hb["missed"] + 1
        return false
    end
    return true

# ============================================================================
# Transport Statistics
# ============================================================================

proc create_transport_stats():
    let stats = {}
    stats["bytes_sent"] = 0
    stats["bytes_recv"] = 0
    stats["messages_sent"] = 0
    stats["messages_recv"] = 0
    stats["errors"] = 0
    return stats

proc record_sent(stats, bytes):
    stats["bytes_sent"] = stats["bytes_sent"] + bytes
    stats["messages_sent"] = stats["messages_sent"] + 1

proc record_recv(stats, bytes):
    stats["bytes_recv"] = stats["bytes_recv"] + bytes
    stats["messages_recv"] = stats["messages_recv"] + 1

proc record_error(stats):
    stats["errors"] = stats["errors"] + 1