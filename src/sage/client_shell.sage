# SMP Client Shell
# ===============
# Interactive client shell for sending messages to any node

gc_disable()

# ============================================================================
# Client State
# ============================================================================

let client_outbox = []
let client_connections = {}

proc client_connect(host, port):
    let conn = {"host": host, "port": port, "connected": true, "last_seen": 0}
    let key = host + ":" + str(port)
    client_connections[key] = conn
    print("Connected to " + host + ":" + str(port))
    return conn

proc client_send(host, port, message):
    let key = host + ":" + str(port)
    if dict_has(client_connections, key):
        let conn = client_connections[key]
        let envelope = {"to": key, "msg": message, "ts": 0}
        push(client_outbox, envelope)
        print("Queued message: " + message)
        return true
    else:
        print("Not connected to " + host + ":" + str(port) + " - use 'connect <host> <port>' first")
        return false

proc client_list_connections():
    print("Active Connections:")
    let keys = dict_keys(client_connections)
    for i in range(len(keys)):
        let conn = client_connections[keys[i]]
        print "  - " + keys[i] + " (connected)"
    return keys

proc client_show_outbox():
    print("Outbox (" + str(len(client_outbox)) + " messages):")
    for i in range(len(client_outbox)):
        let env = client_outbox[i]
        print("  [" + str(i) + "] To: " + env["to"] + " Msg: " + env["msg"])

# ============================================================================
# Shell Interface
# ============================================================================

proc client_shell_help():
    print("Client Shell Commands:")
    print("  connect <host> <port>          - Connect to a node")
    print("  send <host> <port> <message>   - Send message to node")
    print("  list                           - List connections")
    print("  outbox                         - Show queued messages")
    print("  clear_outbox                   - Clear message queue")
    print("  status                         - Show client status")
    print("  help                           - Show this help")
    print("  quit                           - Exit")

proc client_shell_demo():
    print("=== SageSMP Client Shell Demo ===")
    print("")
    
    # Simulate shell commands
    print("Shell> connect 192.168.1.100 42001")
    client_connect("192.168.1.100", 42001)
    
    print "Shell> connect 192.168.1.101 42002"
    client_connect("192.168.1.101", 42002)
    
    print "Shell> connect 127.0.0.1 42000"
    client_connect("127.0.0.1", 42000)
    print ""
    
    client_list_connections()
    print ""
    
    print "Shell> send 192.168.1.100 42001 Hello node!"
    client_send("192.168.1.100", 42001, "Hello node!")
    
    print "Shell> send 127.0.0.1 42000 Ping from client"
    client_send("127.0.0.1", 42000, "Ping from client")
    print ""
    
    client_show_outbox()
    print ""
    
    print "Shell> clear_outbox"
    client_outbox = []
    print "Outbox cleared"
    print ""
    
    print "=== Demo Complete ==="

client_shell_demo()