# Run real SMP Client
gc_disable()

import sys
import io
import smp.client as smp_client

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

let name = "RPi-Client"
if len(args) > 0:
    name = args[0]
end

let mode = "listen"
if len(args) > 1:
    mode = args[1]
end

let target_id = 0
let send_msg = ""
let server_ip = "127.0.0.1"

if mode == "send":
    if len(args) > 2:
        target_id = tonumber(args[2])
    end
    if len(args) > 3:
        send_msg = args[3]
    end
    if len(args) > 4:
        server_ip = args[4]
    end
else:
    if len(args) > 2:
        server_ip = args[2]
    end
end

print "=== Starting Real SMP Client: " + name + " in " + mode + " mode ==="

let client = smp_client.create_client(name, "127.0.0.1", 42001)
print "My Node ID: " + str(client.node["id"])

# Connect to OrangePi server
print "Connecting to server at " + server_ip + ":42000..."
client.connect(server_ip, 42000)

# Set handler for incoming messages
proc on_any(msg):
    print "Client " + name + " received: " + str(msg["payload"])
end

client.on("*", on_any)

if mode == "send":
    print "Sending message to node-" + str(target_id) + ": " + send_msg
    client.send(target_id, send_msg)
    import thread
    thread.sleep(2.0) # Sleep 2 seconds to flush socket
else:
    # Listen mode: Write Node ID to a file in the home directory
    io.writefile(sys.getenv("HOME") + "/node_id", str(client.node["id"]))
    print "Waiting for message..."
    client.poll()
    print "Exiting cleanly after receiving message."
end
