# Run real SMP Server
gc_disable()

import sys
import smp.server as smp_server
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport

let port = 42000
let host = "0.0.0.0"

print "=== Starting Real SMP Server on " + host + ":" + str(port) + " ==="

let server = smp_server.create_server("OrangePi-Relay", host, port)

# Set join event handler
proc on_join(node_id, node):
    print "Server accepted join from node-" + str(node_id) + " (" + node["name"] + ")"
    if dict_has(server.clients, str(node_id)):
        let client_sock = server.clients[str(node_id)]
        let ack = smp_protocol.build_data(0, node_id, "JOIN_ACK")
        smp_transport.send_message(client_sock, ack)
    end
end

server.on("join", on_join)

# Set message event handler
proc on_message(sender, target, payload):
    print "Server routed message from node-" + str(sender) + " to node-" + str(target) + ": " + str(payload)
end

server.on("message", on_message)

# Run server
server.start()
