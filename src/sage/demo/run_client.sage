# Run real SMP Client
gc_disable()

import sys
import io
import smp.client as smp_client

let name = "RPi-Client"
if len(sys.argv) > 1:
    name = sys.argv[1]
end

let target_id = 0
if len(sys.argv) > 2:
    target_id = tonumber(sys.argv[2])
end

let server_ip = "127.0.0.1"
if len(sys.argv) > 3:
    server_ip = sys.argv[3]
end

print "=== Starting Real SMP Client: " + name + " ==="

let client = smp_client.create_client(name, "127.0.0.1", 42001)
print "My Node ID: " + str(client.node["id"])

# Write Node ID to a file in the home directory
io.writefile(sys.getenv("HOME") + "/node_id", str(client.node["id"]))

# Connect to OrangePi server
print "Connecting to server at " + server_ip + ":42000..."
client.connect(server_ip, 42000)

# Set handler for incoming messages
client.on("*", proc(msg):
    print "Client " + name + " received: " + str(msg["payload"])
end)

# Loop and poll for messages
let count = 0
while count < 30:
    count = count + 1
    sys.sleep(1000) # Sleep 1 second
    client.poll()
    
    # On count == 5, send a message to target_id (if target_id is specified)
    if count == 5 and target_id != 0:
        print "Sending message to node-" + str(target_id)
        client.send(target_id, "Hello from client " + name)
    end
end
