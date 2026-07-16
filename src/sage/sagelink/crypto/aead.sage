import crypto.chacha20 as chacha20
import crypto.poly1305 as poly1305

proc pad16(bytes):
    let b = []
    for i in range(len(bytes)):
        push(b, bytes[i])
    while len(b) % 16 != 0:
        push(b, 0)
    return b

proc chacha20_poly1305_encrypt(key, nonce, plaintext, aad):
    let otk_block = chacha20.chacha20_block(key, 0, nonce)
    let otk = []
    for i in range(32):
        push(otk, otk_block[i])

    let ciphertext = chacha20.chacha20_encrypt(key, 1, nonce, plaintext)

    let mac_data = []
    let aad_padded = pad16(aad)
    for i in range(len(aad_padded)):
        push(mac_data, aad_padded[i])
    let ct_padded = pad16(ciphertext)
    for i in range(len(ct_padded)):
        push(mac_data, ct_padded[i])
    let aad_len_bytes = []
    let aad_len = len(aad)
    for i in range(8):
        push(aad_len_bytes, aad_len & 255)
        aad_len = aad_len >> 8
    for i in range(8):
        push(mac_data, aad_len_bytes[i])
    let ct_len = len(ciphertext)
    for i in range(8):
        push(mac_data, ct_len & 255)
        ct_len = ct_len >> 8

    let tag = poly1305.poly1305_mac(otk, mac_data)
    return {"ciphertext": ciphertext, "tag": tag}

proc chacha20_poly1305_decrypt(key, nonce, ciphertext, tag, aad):
    let otk_block = chacha20.chacha20_block(key, 0, nonce)
    let otk = []
    for i in range(32):
        push(otk, otk_block[i])

    let mac_data = []
    let aad_padded = pad16(aad)
    for i in range(len(aad_padded)):
        push(mac_data, aad_padded[i])
    let ct_padded = pad16(ciphertext)
    for i in range(len(ct_padded)):
        push(mac_data, ct_padded[i])
    let aad_len = len(aad)
    for i in range(8):
        push(mac_data, aad_len & 255)
        aad_len = aad_len >> 8
    let ct_len = len(ciphertext)
    for i in range(8):
        push(mac_data, ct_len & 255)
        ct_len = ct_len >> 8

    let expected_tag = poly1305.poly1305_mac(otk, mac_data)
    if len(expected_tag) != len(tag):
        return nil
    for i in range(len(tag)):
        if expected_tag[i] != tag[i]:
            return nil

    return chacha20.chacha20_encrypt(key, 1, nonce, ciphertext)
