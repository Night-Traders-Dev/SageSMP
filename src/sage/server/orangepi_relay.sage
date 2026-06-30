# OrangePi Relay Server
# ====================
# SMP relay server for OrangePi - central hub for RPi clients

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
# Client Registry
# ============================================================================

let clients = {}
let client_info = {}

proc register_client(client_id, host, port, platform):
    let client = {}
    client["id"] = client_id
    client["host"] = host
    client["port"] = port
    client["platform"] = platform
    client["last_update"] = clock()
    clients[str(client_id)] = client
    client_info[str(client_id)] = {}
    print("Registered client " + str(client_id) + " (" + platform + ") from " + host + ":" + str(port))

proc unregister_client(client_id):
    if dict_has(clients, str(client_id)):
        dict_delete(clients, str(client_id))
    if dict_has(client_info, str(client_id)):
        dict_delete(client_info, str(client_id))
    print("Unregistered client " + str(client_id))

proc update_client_info(client_id, info):
    if dict_has(client_info, str(client_id)):
        client_info[str(client_id)] = info
        clients[str(client_id)]["last_update"] = clock()

proc get_client_by_platform(platform):
    let result = []
    let ids = dict_keys(clients)
    for i in range(len(ids)):
        let c = clients[ids[i]]
        if c["platform"] == platform:
            push(result, c)
    return result

proc broadcast_to_all(message, secret_key, otp_pass, otp_seed):
    let ids = dict_keys(clients)
    for i in range(len(ids)):
        let c = clients[ids[i]]
        print("Broadcasting to client " + str(c["id"]) + " at " + c["host"] + ":" + str(c["port"]))
        let env = create_secure_message(message, secret_key, otp_pass, otp_seed, 0, c["id"])
        # In real implementation, send via network
    return len(ids)

# ============================================================================
# Info Exchange Handler
# ============================================================================

proc handle_info_exchange(sender_id, payload):
    let decrypted = read_secure_message(payload, SMP_SECRET, SMP_OTP_PASS, SMP_OTP_SEED, sender_id)
    if decrypted != nil:
        print("Received info from client " + str(sender_id) + ": " + decrypted)
        update_client_info(sender_id, decrypted)

# ============================================================================
# Configuration
# ============================================================================

let SMP_SECRET = "orangepi_cluster_secret_2026"
let SMP_OTP_PASS = "cluster_otp_passphrase"
let SMP_OTP_SEED = 42424
let RELAY_PORT = 42000

# ============================================================================
# Main Loop
# ============================================================================

proc run_orangepi_relay():
    print("=== OrangePi Relay Server ===")
    print("Listening on 0.0.0.0:" + str(RELAY_PORT))
    print("Secret: " + SMP_SECRET)
    print("")
    
    # Wait for clients to connect and send periodic info
    let tick = 0
    while tick < 100:
        tick = tick + 1
        
        # Print connected clients every 10 ticks
        if tick % 10 == 0:
            let ids = dict_keys(clients)
            print("Connected clients: " + str(len(ids)))
            for i in range(len(ids)):
                let c = clients[ids[i]]
                print("  - " + c["platform"] + " (id=" + str(c["id"]) + ")")
        
        # Simulate receiving info from RPi clients
        if tick == 5:
            let rpi2_info = create_secure_message("Temp: 45C, Load: 0.45", SMP_SECRET, SMP_OTP_PASS, SMP_OTP_SEED, 1, 0)
            register_client(1, "192.168.1.20", 42001, "RPi2")
            update_client_info(1, "Temp: 45C, Load: 0.45")
        
        if tick == 8:
            let rpi4_info = create_secure_message("Temp: 52C, Load: 0.78, Available: 8GB", SMP_SECRET, SMP_OTP_PASS, SMP_OTP_SEED, 2, 0)
            register_client(2, "192.168.1.30", 42002, "RPi4")
            update_client_info(2, "Temp: 52C, Load: 0.78, Available: 8GB")
        
        # Periodic broadcast to all clients
        if tick % 20 == 0:
            let bc_msg = "Cluster heartbeat at tick " + str(tick)
            broadcast_to_all(bc_msg, SMP_SECRET, SMP_OTP_PASS, SMP_OTP_SEED)
    
    print("")
    print("=== Relay Complete ===")

run_orangepi_relay()