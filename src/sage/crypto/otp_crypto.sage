# SMP OTP Encryption
# ==================
# Pure Sage OTP encryption for end-to-end secure messages

gc_disable()

# ============================================================================
# Pure Sage Hash
# ============================================================================

proc simple_hash(value, seed):
    let h = seed
    for i in range(len(str(value))):
        h = ((h * 33) + ord(str(value)[i])) % 1000000007
    return h

# ============================================================================
# OTP Key Generation
# ============================================================================

proc generate_otp_key(passphrase, length, seed):
    let key = []
    for i in range(length):
        let h = simple_hash(passphrase + str(i), seed)
        push(key, (h % 255) - 127)
    return key

# ============================================================================
# Sign/Verify
# ============================================================================

proc sign_message(message, secret_key, node_id):
    let sig = simple_hash(message + secret_key + str(node_id), 12345)
    let sig2 = simple_hash(str(sig), 54321)
    return [sig, sig2]

proc verify_signature(message, signature, secret_key, node_id):
    let expected = sign_message(message, secret_key, node_id)
    return signature[0] == expected[0] and signature[1] == expected[1]

# ============================================================================
# OTP Encrypt/Decrypt
# ============================================================================

proc otp_encrypt(message, otp_key):
    let encrypted = []
    for i in range(len(str(message))):
        let m_byte = ord(str(message)[i])
        let k_byte = otp_key[i % len(otp_key)]
        push(encrypted, chr((m_byte + k_byte) % 256))
    return "".join(encrypted)

proc otp_decrypt(encrypted, otp_key):
    let decrypted = []
    for i in range(len(str(encrypted))):
        let e_byte = ord(str(encrypted)[i])
        let k_byte = otp_key[i % len(otp_key)]
        let d_byte = (e_byte - k_byte + 256) % 256
        push(decrypted, chr(d_byte))
    return "".join(decrypted)

# ============================================================================
# Secure Message
# ============================================================================

proc create_secure_message(message, secret_key, otp_passphrase, otp_seed, sender_id, recipient_id):
    let key = generate_otp_key(otp_passphrase, len(str(message)), otp_seed)
    let encrypted = otp_encrypt(message, key)
    let sig = sign_message(encrypted, secret_key, sender_id)
    return {
        "payload": encrypted,
        "otp": key,
        "sig": sig,
        "from": sender_id,
        "to": recipient_id
    }

proc read_secure_message(msg, secret_key, otp_passphrase, otp_seed, expected_sender):
    let valid = verify_signature(msg["payload"], msg["sig"], secret_key, expected_sender)
    if not valid:
        return nil
    let key = generate_otp_key(otp_passphrase, len(str(msg["payload"])), otp_seed)
    return otp_decrypt(msg["payload"], key)

# ============================================================================
# Demo
# ============================================================================

proc run_otp_demo():
    print("=== SMP OTP Encryption Demo ===")
    print("")
    
    let secret = "my_secret_key_123"
    let otp_pass = "otp_passphrase_456"
    let message = "Hello secure world!"
    
    print("Creating secure message...")
    let secure = create_secure_message(message, secret, otp_pass, 789, 1, 2)
    print("Encrypted: " + secure["payload"])
    print("")
    
    print("Decrypting message...")
    let decrypted = read_secure_message(secure, secret, otp_pass, 789, 1)
    print("Decrypted: " + decrypted)
    print("")
    
    print("=== Demo Complete ===")

run_otp_demo()