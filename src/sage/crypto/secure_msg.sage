# SMP Build Configuration
# =======================
# User-customizable build settings for relay and client

gc_disable()

# ============================================================================
# Configuration (users can modify these values)
# ============================================================================

let SMP_CONFIG = {
    "relay_host": "0.0.0.0",
    "relay_port": 42000,
    "max_connections": 64,
    "enable_logging": true,
    "log_file": "/tmp/smp_relay.log",
    "default_secret_key": "change_this_key",
    "default_otp_passphrase": "change_this_passphrase",
    "default_otp_seed": 12345
}

let CLIENT_CONFIG = {
    "server_host": "127.0.0.1",
    "server_port": 42000,
    "reconnect_attempts": 3,
    "default_secret_key": "change_this_key",
    "default_otp_passphrase": "change_this_passphrase", 
    "default_otp_seed": 12345
}

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

proc verify_signature(message, signature, secret_key, node_id):
    let expected = sign_message(message, secret_key, node_id)
    return signature[0] == expected[0] and signature[1] == expected[1]

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

# ============================================================================
# Secure Message API (for use by relay/client)
# ============================================================================

proc secure_send(message, secret_key, otp_pass, otp_seed, sender_id, recipient_id):
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

proc secure_receive(envelope, secret_key, otp_pass, otp_seed, expected_sender):
    if not verify_signature(envelope["payload"], envelope["sig"], secret_key, expected_sender):
        return nil
    let key = generate_otp_key(otp_pass, len(str(envelope["payload"])), otp_seed)
    return otp_decrypt(envelope["payload"], key)

proc secure_send_with_config(message, config, sender_id, recipient_id):
    return secure_send(
        message,
        config["default_secret_key"],
        config["default_otp_passphrase"],
        config["default_otp_seed"],
        sender_id,
        recipient_id
    )

proc secure_receive_with_config(envelope, config, expected_sender):
    return secure_receive(
        envelope,
        config["default_secret_key"],
        config["default_otp_passphrase"],
        config["default_otp_seed"],
        expected_sender
    )

# ============================================================================
# Demo
# ============================================================================

proc run_crypto_demo():
    print("=== SMP Secure Message Demo ===")
    print("")
    
    let message = "Hello secure world!"
    let secret = "my_secret_key"
    let otp_pass = "my_otp_passphrase"
    let otp_seed = 999
    
    print("Sending secure message...")
    let envelope = secure_send(message, secret, otp_pass, otp_seed, 1, 2)
    print("Encrypted payload: " + envelope["payload"])
    
    print("")
    print("Receiving and decrypting...")
    let received = secure_receive(envelope, secret, otp_pass, otp_seed, 1)
    print("Decrypted: " + received)
    
    print("")
    print("Using config-based API...")
    let SMP_CONFIG = {"default_secret_key": secret, "default_otp_passphrase": otp_pass, "default_otp_seed": otp_seed}
    let env2 = secure_send_with_config("Another message", SMP_CONFIG, 3, 4)
    print("Encrypted: " + env2["payload"])
    let dec2 = secure_receive_with_config(env2, SMP_CONFIG, 3)
    print("Decrypted: " + dec2)
    
    print("")
    print("=== Demo Complete ===")

run_crypto_demo()