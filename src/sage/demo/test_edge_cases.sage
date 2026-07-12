# SageSMP Edge Cases Test Suite
# ==============================

gc_disable()

import sys
import smp
import smp.mailbox as smp_mailbox
import smp.node as smp_node
import smp.smp_protocol as smp_protocol
import smp.transport as smp_transport
import smp.crypto as smp_crypto

proc assert_true(val, msg):
    if not val:
        print "FAIL: " + msg
        exit(1)
    else:
        print "  PASS: " + msg
    end
end

proc assert_false(val, msg):
    assert_true(not val, msg)
end

proc test_json_edge_cases():
    print "--- Testing JSON / Protocol Edge Cases ---"
    
    # 1. Decode invalid JSON
    let bad_json = "{bad json: 123"
    let parsed = smp_protocol.decode(bad_json)
    assert_true(parsed == nil, "Decoding invalid JSON should return nil")
    
    # 2. Decode empty string
    let parsed_empty = smp_protocol.decode("")
    assert_true(parsed_empty == nil, "Decoding empty string should return nil")
    
    # 3. Decode valid but empty object
    let empty_obj = "{}"
    let parsed_obj = smp_protocol.decode(empty_obj)
    assert_false(parsed_obj == nil, "Decoding empty object should not return nil")
    
    # 4. Message validation with missing keys
    assert_false(smp_protocol.validate({}), "Empty dictionary should be invalid message")
    assert_false(smp_protocol.validate({"op": 1}), "Missing sender/target should be invalid")
    assert_true(smp_protocol.validate({"op": 1, "sender": 2, "target": 3}), "Full message signature should be valid")
end

proc test_transport_edge_cases():
    print "--- Testing Transport / Buffer Edge Cases ---"
    
    # 1. Buffer overflow writing past capacity
    let buf = smp_transport.create_buffer(10)
    let w1 = smp_transport.write_buffer(buf, "12345")
    assert_true(w1, "Write within capacity should succeed")
    let w2 = smp_transport.write_buffer(buf, "678901")
    assert_false(w2, "Write exceeding capacity should fail")
    
    # 2. Read from empty/underfilled buffer
    let empty_read = smp_transport.read_buffer(buf, 20)
    assert_true(empty_read == nil, "Reading more bytes than available should return nil")
    
    # 3. Frame parsing of truncated frames
    let truncated_frame = "00000010{some" # claims length 10 but only has 5 chars
    let parse_res = smp_transport.parse_frame(truncated_frame)
    assert_false(parse_res["ok"], "Parsing truncated frame should return ok = false")
    assert_true(parse_res["remaining"] == truncated_frame, "Remaining should be original buffer on failure")
end

proc test_crypto_edge_cases():
    print "--- Testing Cryptography Edge Cases ---"
    
    # 1. XOR decrypt with wrong key
    let data = "secret content"
    let correct_key = "correct-password"
    let wrong_key = "wrong-password"
    
    let encrypted = smp_crypto.xor_encrypt(data, correct_key)
    let decrypted_wrong = smp_crypto.xor_decrypt(encrypted, wrong_key)
    assert_false(decrypted_wrong == data, "Decryption with wrong key should not match original data")
    
    # 2. Verify signature with modified message
    let node_id = 999
    let secret = "my-shared-secret"
    let sig = smp_crypto.sign_node_id(node_id, secret)
    
    # Verify with modified node ID
    let ver_bad_id = smp_crypto.verify_node_signature(1000, sig, secret)
    assert_false(ver_bad_id, "Signature verification with modified ID should fail")
    
    # Verify with wrong secret
    let ver_bad_secret = smp_crypto.verify_node_signature(node_id, sig, "other-secret")
    assert_false(ver_bad_secret, "Signature verification with wrong secret should fail")
end

proc test_registry_edge_cases():
    print "--- Testing Node Registry Edge Cases ---"
    
    let registry = smp_node.create_registry()
    let node1 = smp_node.create_node(1, "node-1", "127.0.0.1", 42001)
    
    # 1. Retrieve non-existent node
    let retrieved_none = smp_node.get_node_by_name(registry, "non-existent")
    assert_true(retrieved_none == nil, "Retrieving non-existent node by name should return nil")
    
    let retrieved_id_none = smp_node.get_node_by_id(registry, 99)
    assert_true(retrieved_id_none == nil, "Retrieving non-existent node by ID should return nil")
    
    # 2. Register same node twice
    smp_node.register(registry, node1)
    let count1 = smp_node.count_nodes(registry)
    smp_node.register(registry, node1)
    let count2 = smp_node.count_nodes(registry)
    assert_true(count1 == count2, "Registering the same node twice should not increase count")
    
    # 3. Unregister non-existent node
    let unreg = smp_node.unregister(registry, 999)
    assert_false(unreg, "Unregistering non-existent node should return false")
end

proc test_mailbox_edge_cases():
    print "--- Testing Mailbox Edge Cases ---"
    
    # 1. Send/recv on full mailbox
    let mbox = smp_mailbox.create_mailbox(1, 2)
    let msg1 = smp_mailbox.create_message(1, 2, 0, "msg1")
    let msg2 = smp_mailbox.create_message(1, 2, 0, "msg2")
    let msg3 = smp_mailbox.create_message(1, 2, 0, "msg3")
    let s1 = smp_mailbox.send(mbox, msg1)
    let s2 = smp_mailbox.send(mbox, msg2)
    assert_true(s1 > 0 and s2 > 0, "Initial sends should succeed")
    
    # Non-blocking try_send should return false
    let s3_try = smp_mailbox.try_send(mbox, msg3)
    assert_false(s3_try, "try_send to full mailbox should return false")
    
    # Blocking send should raise exception
    let caught = false
    try:
        smp_mailbox.send(mbox, msg3)
    catch err:
        caught = true
    assert_true(caught, "send to full mailbox should raise exception")
    
    # 2. Receive from empty mailbox
    let r1 = smp_mailbox.recv(mbox)
    let r2 = smp_mailbox.recv(mbox)
    assert_true(r1 != nil and r2 != nil, "Successful receives")
    let r3 = smp_mailbox.recv(mbox)
    assert_true(r3 == nil, "Receiving from empty mailbox should return nil")
end

proc run_all():
    print "Running SageSMP Edge Cases Test Suite...\n"
    test_json_edge_cases()
    print ""
    test_transport_edge_cases()
    print ""
    test_crypto_edge_cases()
    print ""
    test_registry_edge_cases()
    print ""
    test_mailbox_edge_cases()
    print "\nAll edge cases tests passed successfully!"
end

run_all()
