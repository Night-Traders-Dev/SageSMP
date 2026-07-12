# SMP Crypto Utilities
# ====================
# Cryptographic helpers for SMP message authentication and encryption

gc_disable()

import smp.smp_protocol as smp_protocol

# ============================================================================
# Simple XOR cipher for message obfuscation
# ============================================================================

from crypto.encoding import b64_encode, b64_decode

proc xor_encrypt(data, key):
    let key_bytes = []
    for i in range(len(str(key))):
        push(key_bytes, ord(str(key)[i]))
    end
    
    let raw_xor = []
    let data_str = str(data)
    for i in range(len(data_str)):
        let key_idx = i % len(key_bytes)
        push(raw_xor, ord(data_str[i]) ^ key_bytes[key_idx])
    end
    return b64_encode(raw_xor)

proc xor_decrypt(data, key):
    let decoded_bytes = b64_decode(data)
    let key_bytes = []
    for i in range(len(str(key))):
        push(key_bytes, ord(str(key)[i]))
    end
    
    let result = ""
    for i in range(len(decoded_bytes)):
        let key_idx = i % len(key_bytes)
        result = result + chr(decoded_bytes[i] ^ key_bytes[key_idx])
    end
    return result

# ============================================================================
# Simple checksum for message integrity
# ============================================================================

proc checksum(data):
    let data_str = str(data)
    let sum = 0
    for i in range(len(data_str)):
        sum = sum + ord(data_str[i])
    end
    return sum % 65536

proc verify_checksum(data, expected):
    return checksum(data) == expected

# ============================================================================
# Node ID Signing
# ============================================================================

proc generate_node_secret():
    let ts = str(clock())
    let h = hash(ts)
    return str(h)

proc sign_node_id(node_id, secret):
    let data = str(node_id) + ":" + secret
    return str(hash(data))

proc verify_node_signature(node_id, signature, secret):
    return sign_node_id(node_id, secret) == signature

# ============================================================================
# Message Authentication
# ============================================================================

proc sign_message(msg, secret):
    let data = smp_protocol.encode(msg)
    let cs = checksum(data)
    return {
        "message": msg,
        "checksum": cs,
        "signature": sign_node_id(msg["sender"], secret)
    }

proc verify_message(signed_msg, secret):
    if not verify_checksum(signed_msg["message"], signed_msg["checksum"]):
        return false
    if not verify_node_signature(signed_msg["message"]["sender"], signed_msg["signature"], secret):
        return false
    return true

# ============================================================================
# Simple Challenge-Response
# ============================================================================

proc create_challenge():
    let ts = clock()
    let random_val = hash(ts + ":" + str(ts * 1000))
    return str(random_val)

proc create_response(challenge, secret):
    return str(hash(challenge + ":" + secret))

proc verify_response(challenge, response, secret):
    return create_response(challenge, secret) == response

# ============================================================================
# Token Generation
# ============================================================================

proc generate_token(node_id, secret, ttl_secs):
    let expires = clock() + ttl_secs
    let data = str(node_id) + ":" + str(expires) + ":" + secret
    return {
        "token": str(hash(data)),
        "node_id": node_id,
        "expires": expires
    }

proc validate_token(token, secret):
    if clock() > token["expires"]:
        return false
    let data = str(token["node_id"]) + ":" + str(token["expires"]) + ":" + secret
    return hash(data) == tonumber(token["token"])

# ============================================================================
# Envelope Encryption (simplified)
# ============================================================================

proc create_secure_envelope(sender_id, recipient_id, payload, secret):
    let key = secret
    let encrypted = xor_encrypt(payload, key)
    return {
        "sender": sender_id,
        "recipient": recipient_id,
        "payload": encrypted,
        "checksum": checksum(payload),
        "ts": clock()
    }

proc open_secure_envelope(envelope, secret):
    let payload = xor_decrypt(envelope["payload"], secret)
    if not verify_checksum(payload, envelope["checksum"]):
        raise "checksum verification failed"
    return payload