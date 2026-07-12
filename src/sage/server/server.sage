# SMP Server
# ==========
# Server implementation for SMP protocol

gc_disable()

import sys
import smp
import smp.mailbox as smp_mailbox
import smp.node as smp_node
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport

let SMP_OP_HEARTBEAT = smp.SMP_OP_HEARTBEAT
let SMP_OP_MESSAGE = smp.SMP_OP_MESSAGE
let SMP_OP_JOIN = smp.SMP_OP_JOIN
let SMP_OP_LEAVE = smp.SMP_OP_LEAVE
let SMP_OP_MAILBOX = smp.SMP_OP_MAILBOX
let SMP_OP_SYNC = smp.SMP_OP_SYNC

class Server:
    proc init(self, name, host, port):
        let registry_and_node = smp_node.create_local_node(name, host, port)
        self.registry = registry_and_node[0]
        self.node = registry_and_node[1]
        self.server_socket = smp_transport.create_tcp_server(port)
        self.mailboxes = {}
        self.clients = {}
        self.handlers = {}
        self.running = false
        self.heartbeat_interval = 1.0
        self.max_clients = smp.DEFAULT_MAX_NODES
    
    proc start(self):
        self.running = true
        print("SMP Server starting on " + self.node["host"] + ":" + str(self.node["port"]))
        
        while self.running:
            let client = smp_transport.accept(self.server_socket)
            if client != nil:
                handle_client(self, client)
            end
            sys.sleep(10)
        end
    
    proc stop(self):
        self.running = false
        smp_transport.close(self.server_socket)
    
    proc handle_client(self, client):
        while client["connected"]:
            let raw = smp_transport.recv_message(client)
            if raw != nil:
                handle_message(self, client, raw)
            end
    
    proc handle_message(self, client, raw_msg):
        let msg = smp_protocol.decode(raw_msg)
        
        if msg["op"] == SMP_OP_JOIN:
            handle_join(self, client, msg)
        elif msg["op"] == SMP_OP_LEAVE:
            handle_leave(self, client, msg)
        elif msg["op"] == SMP_OP_MESSAGE:
            handle_message_data(self, client, msg)
        elif msg["op"] == SMP_OP_MAILBOX:
            handle_mailbox(self, client, msg)
        elif msg["op"] == SMP_OP_HEARTBEAT:
            update_heartbeat(self, msg["sender"])
        end
    
    proc handle_join(self, client, msg):
        let node_info = msg["payload"]
        let node_id = msg["sender"]
        
        let node = smp_node.create_node(node_id, node_info["name"], client["host"], client["port"])
        node["capabilities"] = node_info["capabilities"]
        
        smp_node.register(self.registry, node)
        smp_node.ready(self.registry, node)
        
        let mbox = smp_mailbox.create_mailbox(node_id, DEFAULT_MAILBOX_SIZE)
        self.mailboxes[str(node_id)] = mbox
        
        self.clients[str(node_id)] = client
        
        print("Node joined: " + str(node_id) + " (" + str(node_info["name"]) + ")")
    
    proc handle_leave(self, client, msg):
        let node_id = msg["sender"]
        smp_node.unregister(self.registry, node_id)
        
        if dict_has(self.mailboxes, str(node_id)):
            let mbox = self.mailboxes[str(node_id)]
            smp_mailbox.close(mbox)
            dict_delete(self.mailboxes, str(node_id))
        end
        
        if dict_has(self.clients, str(node_id)):
            dict_delete(self.clients, str(node_id))
        end
        
        print("Node left: " + str(node_id))
    
    proc handle_message_data(self, client, msg):
        let target_id = msg["target"]
        let sender_id = msg["sender"]
        
        if dict_has(self.mailboxes, str(target_id)):
            let target_mbox = self.mailboxes[str(target_id)]
            smp_mailbox.send(target_mbox, msg)
        end
        
        if dict_has(self.handlers, "message"):
            let handlers = self.handlers["message"]
            for i in range(len(handlers)):
                handlers[i](sender_id, target_id, msg["payload"])
            end
        end
    
    proc handle_mailbox(self, client, msg):
        let target_id = msg["target"]
        let payload = msg["payload"]
        
        if dict_has(self.mailboxes, str(target_id)):
            let target_mbox = self.mailboxes[str(target_id)]
            smp_mailbox.send(target_mbox, payload)
        end
    
    proc route_message(self, sender_id, target_id, payload):
        let msg = smp_protocol.build_data(sender_id, target_id, payload)
        
        if dict_has(self.mailboxes, str(target_id)):
            let mbox = self.mailboxes[str(target_id)]
            smp_mailbox.send(mbox, msg)
        end
        
        if dict_has(self.clients, str(target_id)):
            let client = self.clients[str(target_id)]
            smp_transport.send_message(client, msg)
        end
    
    proc broadcast(self, payload):
        let msg = smp_protocol.build_broadcast(self.node["id"], payload)
        
        let client_ids = dict_keys(self.clients)
        for i in range(len(client_ids)):
            let client = self.clients[client_ids[i]]
            smp_transport.send_message(client, msg)
        end
    
    proc on(self, event, handler):
        if not dict_has(self.handlers, event):
            self.handlers[event] = []
        push(self.handlers[event], handler)

# ============================================================================
# Server Factory
# ============================================================================

proc create_server(name, host, port):
    return Server(name, host, port)

proc create_server_from_env(name):
    let port_str = sys.getenv("SMP_PORT")
    let port = DEFAULT_PORT
    if port_str != nil:
        port = tonumber(port_str)
    end
    return Server(name, "0.0.0.0", port)

# ============================================================================
# Multi-server Coordination
# ============================================================================

proc create_cluster(servers):
    let cluster = {}
    cluster["servers"] = servers
    cluster["leader"] = nil
    cluster["members"] = []
    return cluster

proc elect_leader(cluster):
    let best_id = -1
    let best_node = nil
    
    for i in range(len(cluster["servers"])):
        let srv = cluster["servers"][i]
        if srv.node["id"] > best_id:
            best_id = srv.node["id"]
            best_node = srv.node
        end
    end
    
    cluster["leader"] = best_node
    return best_node

proc get_leader(cluster):
    return cluster["leader"]

proc is_leader(cluster, server):
    if cluster["leader"] == nil:
        return false
    return cluster["leader"]["id"] == server.node["id"]

# ============================================================================
# Node Routing
# ============================================================================

proc route_to_node(server, node_id):
    if dict_has(server.mailboxes, str(node_id)):
        return server.mailboxes[str(node_id)]
    return nil

proc broadcast_to_all(server, payload):
    let msg = smp_protocol.build_broadcast(server.node["id"], payload)
    
    let client_ids = dict_keys(server.clients)
    for i in range(len(client_ids)):
        let client = server.clients[client_ids[i]]
        smp_transport.send_message(client, msg)
    end

proc send_to_node(server, node_id, payload):
    let msg = smp_protocol.build_data(server.node["id"], node_id, payload)
    
    if dict_has(server.mailboxes, str(node_id)):
        let mbox = server.mailboxes[str(node_id)]
        smp_mailbox.send(mbox, msg)
    end
    
    if dict_has(server.clients, str(node_id)):
        let client = server.clients[str(node_id)]
        smp_transport.send_message(client, msg)
    end