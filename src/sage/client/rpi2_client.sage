# RPi2 Client
# ===========
# OrangePi relay client for Raspberry Pi 2

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
# RPi2 Info Collection (simulated)
# ============================================================================

proc get_cpu_temp():
    # Simulated - in real implementation read from /sys/class/thermal/thermal_zone0/temp
    return 45 + (clock() % 5)

proc get_cpu_load():
    # Simulated - in real implementation read from /proc/loadavg
    return 0.4 + (clock() % 10) / 100.0

proc get_memory_info():
    # RPi2 has 1GB RAM
    return "Available: 768MB"

proc get_rpi2_info():
    let temp = get_cpu_temp()
    let load = get_cpu_load()
    let mem = get_memory_info()
    return "Temp: " + str(temp) + "C, Load: " + str(load) + ", " + mem

# ============================================================================
# OrangePi Relay Connection
# ============================================================================

let SMP_SECRET = "orangepi_cluster_secret_2026"
let SMP_OTP_PASS = "cluster_otp_passphrase"
let SMP_OTP_SEED = 42424
let ORANGEPI_HOST = "192.168.1.10"
let ORANGEPI_PORT = 42000
let CLIENT_ID = 1

proc send_info_to_orangepi(message):
    let envelope = create_secure_message(message, SMP_SECRET, SMP_OTP_PASS, SMP_OTP_SEED, CLIENT_ID, 0)
    print("Sending to OrangePi: " + str(message))
    print("  Encrypted: " + envelope["payload"])
    return envelope

# ============================================================================
# Main Loop - Periodic Info Sharing
# ============================================================================

proc run_rpi2_client():
    print("=== RPi2 Client Starting ===")
    print("Connecting to OrangePi at " + ORANGEPI_HOST + ":" + str(ORANGEPI_PORT))
    print("")
    
    let tick = 0
    while tick < 50:
        tick = tick + 1
        
        # Send periodic info every 5 ticks (simulated seconds)
        if tick % 5 == 0:
            let info = get_rpi2_info()
            send_info_to_orangepi(info)
            print("  -> Sent at tick " + str(tick))
        
        # Simulate receiving broadcast from OrangePi
        if tick % 20 == 0:
            print("Received broadcast from OrangePi: heartbeat tick " + str(tick * 2))
    
    print("")
    print("=== RPi2 Client Complete ===")

run_rpi2_client()