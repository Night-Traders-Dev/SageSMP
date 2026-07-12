# Run real SageSMP store-and-forward test
gc_disable()

import sys
import io
import thread
import smp.client as smp_client
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport

let all_args = sys.args()
let args = []
let found = false
for i in range(len(all_args)):
    if found:
        push(args, all_args[i])
    else:
        let s = all_args[i]
        let is_sage = false
        if len(s) >= 5:
            for j in range(len(s) - 4):
                if s[j] == "." and s[j+1] == "s" and s[j+2] == "a" and s[j+3] == "g" and s[j+4] == "e":
                    is_sage = true
                end
            end
        end
        if is_sage:
            found = true
        end
    end
end

let role = "register"
if len(args) > 0:
    role = args[0]
end

let server_ip = "127.0.0.1"
if len(args) > 1:
    server_ip = args[1]
end

let target_id = 0
if len(args) > 2:
    target_id = tonumber(args[2])
end

let payload = ""
if len(args) > 3:
    payload = args[3]
end

print "=== SMP Cluster Test: " + role + " ==="

if role == "register":
    let client = smp_client.create_client("Listener", "127.0.0.1", 42001)
    print "My ID: " + str(client.node["id"])
    io.writefile(sys.getenv("HOME") + "/node_id", str(client.node["id"]))
    
    print "Registering on server " + server_ip + "..."
    client.connect(server_ip, 42000)
    thread.sleep(1.0)
    print "Registration complete. Exiting."

elif role == "send":
    let client = smp_client.create_client("Sender", "127.0.0.1", 42002)
    print "Connecting and sending to " + str(target_id) + "..."
    client.connect(server_ip, 42000)
    client.send(target_id, payload)
    thread.sleep(2.0)
    print "Message sent. Exiting."

elif role == "poll":
    let client = smp_client.create_client("Listener", "127.0.0.1", 42001)
    # Restore node ID from home directory
    let saved_id_str = io.readfile(sys.getenv("HOME") + "/node_id")
    if saved_id_str != nil:
        client.node["id"] = tonumber(saved_id_str)
    end
    print "Polling server for ID " + str(client.node["id"]) + "..."
    client.connect(server_ip, 42000)
    
    # Request mailbox flush
    let req = smp_protocol.build_mailbox(client.node["id"], 0, 10)
    smp_transport.send_message(client.connection, req)
    
    # Handle incoming messages
    proc on_any(msg):
        print "Received: " + str(msg["payload"])
    end
    client.on("*", on_any)
    
    # Poll to retrieve any flushed messages
    let count = 0
    while count < 3:
        count = count + 1
        client.poll()
        thread.sleep(1.0)
    end
    print "Polling finished. Exiting."
end
