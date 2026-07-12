# Run real SMP Server
gc_disable()

import sys
import smp.server as smp_server
import smp.smp_protocol as smp_protocol

let port = 42000
let host = "0.0.0.0"

print "=== Starting Real SMP Server on " + host + ":" + str(port) + " ==="

let server = smp_server.create_server("OrangePi-Relay", host, port)

# Set message event handler
server.on("message", proc(sender, target, payload):
    print "Server routed message from node-" + str(sender) + " to node-" + str(target) + ": " + str(payload)
end)

# Run server
server.start()
