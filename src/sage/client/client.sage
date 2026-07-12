# SMP Client
# ==========
# Client implementation for SMP protocol

gc_disable()

import sys
import smp
import smp.mailbox as smp_mailbox
import smp.node as smp_node
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport

class Client:
    proc init(self, name, host, port):
        let registry_and_node = smp_node.create_local_node(name, host, port)
        self.registry = registry_and_node[0]
        self.node = registry_and_node[1]
        self.connection = nil
        self.mailbox = smp_mailbox.create_mailbox(self.node["id"], smp.DEFAULT_MAILBOX_SIZE)
        self.node["mailbox"] = self.mailbox
        self.handlers = {}
        self.running = false
        self.heartbeat = smp_transport.create_heartbeat(1.0)
        self.stats = smp_transport.create_transport_stats()
    
    proc connect(self, target_host, target_port):
        self.connection = smp_transport.create_connection(self.node)
        smp_transport.open_connection(self.connection, target_host, target_port)
        
        let join_msg = smp_protocol.build_join(self.node["id"], {
            "name": self.node["name"],
            "capabilities": self.node["capabilities"]
        })
        
        smp_transport.send_message(self.connection, join_msg)
        smp_node.ready(self.registry, self.node)
        return true
    
    proc disconnect(self):
        if self.connection != nil:
            let leave_msg = smp_protocol.build_leave(self.node["id"])
            smp_transport.send_message(self.connection, leave_msg)
            smp_transport.close_connection(self.connection)
            self.connection = nil
        end
        
        smp_node.disconnect(self.registry, self.node)
        return true
    
    proc send(self, target_id, payload):
        let msg = smp_protocol.build_data(self.node["id"], target_id, payload)
        let seq = smp_mailbox.send(self.mailbox, msg)
        smp_transport.send_message(self.connection, msg)
        smp_transport.record_sent(self.stats, len(str(payload)))
        return seq
    
    proc broadcast(self, payload):
        let msg = smp_protocol.build_broadcast(self.node["id"], payload)
        smp_transport.send_message(self.connection, msg)
        return true
    
    proc on(self, msg_type, handler):
        if not dict_has(self.handlers, msg_type):
            self.handlers[msg_type] = []
        push(self.handlers[msg_type], handler)
    
    proc handle_message(self, raw_msg):
        let msg = smp_protocol.decode(raw_msg)
        
        if dict_has(self.handlers, str(msg["op"])):
            let handlers = self.handlers[str(msg["op"])]
            for i in range(len(handlers)):
                handlers[i](msg)
        end
        
        if dict_has(self.handlers, "*"):
            let handlers = self.handlers["*"]
            for i in range(len(handlers)):
                handlers[i](msg)
        end
        
        record_recv(self.stats, len(str(raw_msg)))
    
    proc poll(self):
        if self.connection == nil:
            return nil
        
        let raw = smp_transport.recv_message(self.connection)
        if raw != nil:
            handle_message(self, raw)
        end
        
        return raw
    
    proc process_mailbox(self):
        smp_mailbox.process(self.mailbox)
    
    proc tick(self):
        poll(self)
        process_mailbox(self)
        
        if smp_transport.should_ping(self.connection, 1.0):
            let hb_msg = smp_protocol.build_heartbeat(self.node["id"], 0)
            smp_transport.send_message(self.connection, hb_msg)
            smp_transport.ping(self.connection)
        end
    
    proc run(self):
        self.running = true
        while self.running:
            tick(self)
            sys.sleep(10)
        end
    
    proc stop(self):
        self.running = false
        self.disconnect()
    
    proc get_stats(self):
        let s = {}
        s["node_id"] = self.node["id"]
        s["node_name"] = self.node["name"]
        s["state"] = self.node["state"]
        s["transport"] = self.stats
        s["mailbox"] = smp_mailbox.get_stats(self.mailbox)
        return s

# ============================================================================
# Client Factory
# ============================================================================

proc create_client(name, host, port):
    return Client(name, host, port)

proc create_client_from_env(name):
    let host = sys.getenv("SMP_HOST")
    if host == nil:
        host = smp.DEFAULT_HOST
    end
    let port_str = sys.getenv("SMP_PORT")
    let port = smp.DEFAULT_PORT
    if port_str != nil:
        port = tonumber(port_str)
    end
    return Client(name, host, port)

# ============================================================================
# Sync Operations
# ============================================================================

proc sync_state(client, target_id, state_data):
    let msg = smp_protocol.build_sync(client.node["id"], target_id, state_data)
    smp_mailbox.send(client.mailbox, msg)
    smp_transport.send_message(client.connection, msg)
    return true

proc request_sync(client, target_id):
    let msg = smp_protocol.build_sync(client.node["id"], target_id, nil)
    smp_transport.send_message(client.connection, msg)
    return true