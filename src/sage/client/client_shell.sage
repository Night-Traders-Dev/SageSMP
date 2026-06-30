# SMP Client Shell
# ===============
# Interactive client shell for sending OTP-encrypted messages

gc_disable()

# ============================================================================
# Pure Sage Hash (same as relay)
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

# ============================================================================
# Client Connection
# ============================================================================

let client_outbox = []
let client_connections = {}

proc client_connect(host, port):
    let conn = {"host": host, "port": port}
    let key = host + ":" + str(port)
    client_connections[key] = conn
    print("Connected to " + host + ":" + str(port))
    return conn

proc client_send_secure(host, port, message, secret_key, otp_pass, otp_seed, sender_id, recipient_id):
    let key = host + ":" + str(port)
    if not dict_has(client_connections, key):
        print("Not connected to " + host + ":" + str(port))
        return false
    
    let otp_key = generate_otp_key(otp_pass, len(str(message)), otp_seed)
    let encrypted = otp_encrypt(message, otp_key)
    let sig = sign_message(encrypted, secret_key, sender_id)
    
    let envelope = {
        "to": key,
        "payload": encrypted,
        "otp": otp_key,
        "sig": sig,
        "from": sender_id,
        "ts": 0
    }
    
    push(client_outbox, envelope)
    print("Queued secure message to " + key)
    return true

# ============================================================================
# Demo
# ============================================================================

proc run_client_demo():
    print("=== SageSMP Client Shell Demo (OTP-Encrypted) ===")
    print("")
    
    print("Shell> connect 192.168.1.100 42001")
    client_connect("192.168.1.100", 42001)
    
    print("Shell> connect 127.0.0.1 42000")
    client_connect("127.0.0.1", 42000)
    print("")
    
    print("Active connections:")
    let keys = dict_keys(client_connections)
    for i in range(len(keys)):
        print("  - " + keys[i])
    print("")
    
    print("Shell> send_secure 192.168.1.100 42001 'Secret message!' mysecret mypass 999 10 5")
    client_send_secure("192.168.1.100", 42001, "Secret message!", "mysecret", "mypass", 999, 10, 5)
    
    print("Shell> send_secure 127.0.0.1 42000 'Status update' statuskey statuspass 888 10 1")
    client_send_secure("127.0.0.1", 42000, "Status update", "statuskey", "statuspass", 888, 10, 1)
    print("")
    
    print("Outbox (" + str(len(client_outbox)) + " secure messages):")
    for i in range(len(client_outbox)):
        let env = client_outbox[i]
        print("  [" + str(i) + "] To: " + env["to"])
        print("      Encrypted: " + env["payload"])
    
    print("")
    print("=== Demo Complete ===")

run_client_demo()