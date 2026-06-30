# SMP Example Usage and Tests
# ============================
# Demonstrates the SageSMP multicore protocol

gc_disable()

import sys
import smp
import smp.mailbox as smp_mailbox
import smp.node as smp_node
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport
import smp.crypto as smp_crypto

# Constants from init
let MSG_TYPE_DATA = smp.MSG_TYPE_DATA
let SMP_OP_HEARTBEAT = smp.SMP_OP_HEARTBEAT
let SMP_OP_JOIN = smp.SMP_OP_JOIN

# ============================================================================
# Basic Mailbox Test
# ============================================================================

proc test_mailbox():
    print "=== Testing Mailbox ==="
    
    let mbox = smp_mailbox.create_mailbox(1, 10)
    
    # Send some messages
    let msg1 = smp_mailbox.create_message(1, 2, MSG_TYPE_DATA, "Hello from node 1")
    let msg2 = smp_mailbox.create_message(1, 2, MSG_TYPE_DATA, "Second message")
    
    let seq1 = smp_mailbox.send(mbox, msg1)
    let seq2 = smp_mailbox.send(mbox, msg2)
    
    print "Sent message 1 with seq: " + str(seq1)
    print "Sent message 2 with seq: " + str(seq2)
    
    # Receive messages
    let received = smp_mailbox.recv(mbox)
    print "Received: " + str(received["payload"])
    
    print "Mailbox stats: " + str(smp_mailbox.get_stats(mbox))
    return true

# ============================================================================
# Node Registration Test
# ============================================================================

proc test_node_registry():
    print "\n=== Testing Node Registry ==="
    
    let registry = smp_node.create_registry()
    
    let node1 = smp_node.create_node(1, "node-alpha", "127.0.0.1", 42001)
    let node2 = smp_node.create_node(2, "node-beta", "127.0.0.1", 42002)
    
    smp_node.register(registry, node1)
    smp_node.register(registry, node2)
    
    print "Total nodes: " + str(smp_node.count_nodes(registry))
    print "Connected nodes: " + str(smp_node.count_connected(registry))
    
    let retrieved = smp_node.get_node_by_name(registry, "node-alpha")
    print "Found node by name: " + str(retrieved["id"])
    
    return true

# ============================================================================
# Protocol Encoding Test
# ============================================================================

proc test_protocol():
    print "\n=== Testing Protocol ==="
    
    let msg = smp_protocol.build_data(1, 2, {"cmd": "test", "value": 42})
    print "Built message: op=" + smp_protocol.opcode_name(msg["op"])
    
    let join_msg = smp_protocol.build_join(1, {"name": "test-node"})
    print "Join message opcode: " + smp_protocol.opcode_name(join_msg["op"])
    
    let encoded = smp_protocol.encode(msg)
    print "Encoded: " + encoded
    
    return true

# ============================================================================
# Transport Test
# ============================================================================

proc test_transport():
    print "\n=== Testing Transport ==="
    
    let framed = smp_transport.frame_message({"test": "data"})
    print "Framed message length: " + str(len(framed))
    
    let buf = smp_transport.create_buffer(65536)
    smp_transport.write_buffer(buf, framed)
    print "Buffer data length: " + str(len(buf["data"]))
    
    return true

# ============================================================================
# Crypto Test
# ============================================================================

proc test_crypto():
    print "\n=== Testing Crypto ==="
    
    let secret = "my-secret-key"
    let data = "sensitive message"
    
    let encrypted = smp_crypto.xor_encrypt(data, secret)
    print "Encrypted: " + encrypted
    
    let decrypted = smp_crypto.xor_decrypt(encrypted, secret)
    print "Decrypted: " + decrypted
    
    let cs = smp_crypto.checksum(data)
    print "Checksum valid: " + str(smp_crypto.verify_checksum(data, cs))
    
    let node_id = 12345
    let sig = smp_crypto.sign_node_id(node_id, secret)
    print "Signature valid: " + str(smp_crypto.verify_node_signature(node_id, sig, secret))
    
    return true

# ============================================================================
# Full Integration Test
# ============================================================================

proc test_integration():
    print "\n=== Testing Integration ==="
    
    # Create a local node
    let registry_and_node = smp_node.create_local_node("test-node", "127.0.0.1", 42000)
    let registry = registry_and_node[0]
    let node = registry_and_node[1]
    
    print "Local node created: " + str(node["id"]) + " (" + node["name"] + ")"
    
    # Create mailbox
    let mbox = smp_mailbox.create_mailbox(node["id"], 100)
    
    # Send and receive
    let msg = smp_mailbox.create_message(node["id"], 0, MSG_TYPE_DATA, "Integration test")
    let seq = smp_mailbox.send(mbox, msg)
    print "Message sent with seq: " + str(seq)
    
    let received = smp_mailbox.recv(mbox)
    print "Message received: " + str(received["payload"])
    
    return true

# ============================================================================
# Run all tests
# ============================================================================

proc run_all():
    print "Running SageSMP tests...\n"
    
    test_mailbox()
    test_node_registry()
    test_protocol()
    test_transport()
    test_crypto()
    test_integration()
    
    print "\n=== All tests passed ==="
    return true

# Uncomment to run tests
# run_all()