# SMP Relay Server
# ===============
# Configurable relay server with OTP-encrypted message forwarding

gc_disable()

# ============================================================================
# Pure Sage Hash
# ============================================================================

proc simple_hash(value, seed):
    let h = seed
    for i in range(len(str(value))):
        h = ((h * 33) + ord(str(value)[i])) % 1000000007
    return h

proc generate_otp_key(passphrase, length, seed):
    let key = []
    for i in range(length):
        let h = simple_hash(passphrase + str(i), seed)
        push(key, (h % 255) - 127)
    return key

proc sign_message(message, secret_key, node_id):
    let sig = simple_hash(message + secret_key + str(node_id), 12345)
    let sig2 = simple_hash(str(sig), 54321)
    return [sig, sig2]

proc otp_encrypt(message, otp_key):
    let encrypted = ""
    for i in range(len(str(message))):
        let m_byte = ord(str(message)[i])
        let k_byte = otp_key[i % len(otp_key)]
        encrypted = encrypted + chr((m_byte + k_byte) % 256)
    return encrypted

proc otp_decrypt(encrypted, otp_key):
    let decrypted = ""
    for i in range(len(str(encrypted))):
        let e_byte = ord(str(encrypted)[i])
        let k_byte = otp_key[i % len(otp_key)]
        let d_byte = (e_byte - k_byte + 256) % 256
        decrypted = decrypted + chr(d_byte)
    return decrypted

proc create_secure_message(message, secret_key, otp_pass, otp_seed, sender_id, recipient_id):
    let key = generate_otp_key(otp_pass, len(str(message)), otp_seed)
    let encrypted = otp_encrypt(message, key)
    let sig = sign_message(encrypted, secret_key, sender_id)
    return {
        "payload": encrypted,
        "otp": key,
        "sig": sig,
        "from": sender_id,
        "to": recipient_id
    }

proc read_secure_message(msg, secret_key, otp_pass, otp_seed, expected_sender):
    let valid = verify_signature(msg["payload"], msg["sig"], secret_key, expected_sender)
    if not valid:
        return nil
    let key = generate_otp_key(otp_pass, len(str(msg["payload"])), otp_seed)
    return otp_decrypt(msg["payload"], key)

proc verify_signature(message, signature, secret_key, node_id):
    let expected = sign_message(message, secret_key, node_id)
    return signature[0] == expected[0] and signature[1] == expected[1]

# ============================================================================
# Relay Configuration
# ============================================================================

let relay_rules = []

proc add_relay_rule(trigger_msg, target_host, target_port, forward_msg, secret_key, otp_pass, otp_seed):
    let rule = {}
    rule["trigger"] = trigger_msg
    rule["target_host"] = target_host
    rule["target_port"] = target_port
    rule["forward"] = forward_msg
    rule["secret_key"] = secret_key
    rule["otp_pass"] = otp_pass
    rule["otp_seed"] = otp_seed
    push(relay_rules, rule)
    return len(relay_rules) - 1

proc secure_forward(msg, rule):
    return create_secure_message(
        rule["forward"],
        rule["secret_key"],
        rule["otp_pass"],
        rule["otp_seed"],
        0,
        msg["sender_id"]
    )

proc relay_process_message(msg):
    for i in range(len(relay_rules)):
        let rule = relay_rules[i]
        if msg["payload"] == rule["trigger"]:
            print("Relay: Triggering rule " + str(i) + " for message: " + msg["payload"])
            let forwarded = secure_forward(msg, rule)
            print("Relay: Forwarding encrypted payload to " + rule["target_host"] + ":" + str(rule["target_port"]))
            return forwarded
    return nil

proc list_relay_rules():
    print("Relay Rules:")
    for i in range(len(relay_rules)):
        let r = relay_rules[i]
        print("  [" + str(i) + "] Trigger: '" + r["trigger"] + "' -> " + r["target_host"] + ":" + str(r["target_port"]))

# ============================================================================
# Demo
# ============================================================================

proc run_relay_demo():
    print("=== SageSMP Relay Server Demo (OTP-Encrypted) ===")
    print("")
    
    print("Adding secure relay rules...")
    add_relay_rule("hello", "192.168.1.100", 42001, "Hello from relay!", "secret1", "pass1", 100)
    add_relay_rule("status", "192.168.1.100", 42001, "Status: OK", "secret2", "pass2", 200)
    print("")
    
    list_relay_rules()
    print("")
    
    print("Simulating received messages:")
    
    print("Received: hello")
    let msg1 = {"sender_id": 10, "payload": "hello"}
    let fwd1 = relay_process_message(msg1)
    if fwd1 != nil:
        print("  -> Forwarded encrypted: " + fwd1["payload"])
        let dec1 = read_secure_message(fwd1, "secret1", "pass1", 100, 0)
        print("  -> Decrypted: " + dec1)
    
    print("Received: status")
    let msg2 = {"sender_id": 11, "payload": "status"}
    let fwd2 = relay_process_message(msg2)
    if fwd2 != nil:
        print("  -> Forwarded encrypted: " + fwd2["payload"])
    
    print("Received: unknown")
    let msg3 = {"sender_id": 12, "payload": "unknown"}
    let fwd3 = relay_process_message(msg3)
    if fwd3 == nil:
        print("  -> No matching rule")
    
    print("")
    print("=== Demo Complete ===")

run_relay_demo()