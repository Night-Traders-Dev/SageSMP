proc u32(x):
    return x & 4294967295

proc rotl32(x, n):
    return u32((x << n) | (x >> (32 - n)))

proc le_bytes_to_u32(b, off):
    return b[off] | (b[off+1] << 8) | (b[off+2] << 16) | (b[off+3] << 24)

proc u32_to_le_bytes(val):
    let b = []
    for i in range(4):
        push(b, (val >> (8 * i)) & 255)
    return b

proc quarter_round(a, b, c, d):
    a = u32(a + b)
    d = rotl32(u32(d ^ a), 16)
    c = u32(c + d)
    b = rotl32(u32(b ^ c), 12)
    a = u32(a + b)
    d = rotl32(u32(d ^ a), 8)
    c = u32(c + d)
    b = rotl32(u32(b ^ c), 7)
    return [a, b, c, d]

proc do_qr(w, i0, i1, i2, i3):
    let r = quarter_round(w[i0], w[i1], w[i2], w[i3])
    w[i0] = r[0]
    w[i1] = r[1]
    w[i2] = r[2]
    w[i3] = r[3]

proc chacha20_block(key, counter, nonce):
    let k = []
    for i in range(8):
        push(k, le_bytes_to_u32(key, i * 4))
    let n = []
    for i in range(3):
        push(n, le_bytes_to_u32(nonce, i * 4))

    let state = [1634760805, 857760878, 2036477234, 1797285236,
                 k[0], k[1], k[2], k[3], k[4], k[5], k[6], k[7],
                 counter, n[0], n[1], n[2]]

    let w = []
    for i in range(16):
        push(w, state[i])

    for i in range(10):
        do_qr(w, 0, 4, 8, 12)
        do_qr(w, 1, 5, 9, 13)
        do_qr(w, 2, 6, 10, 14)
        do_qr(w, 3, 7, 11, 15)
        do_qr(w, 0, 5, 10, 15)
        do_qr(w, 1, 6, 11, 12)
        do_qr(w, 2, 7, 8, 13)
        do_qr(w, 3, 4, 9, 14)

    let out = []
    for i in range(16):
        let val = u32(w[i] + state[i])
        let le = u32_to_le_bytes(val)
        for j in range(4):
            push(out, le[j])
    return out

proc chacha20_encrypt(key, counter, nonce, plaintext):
    let pt = []
    if type(plaintext) == "string":
        for i in range(len(plaintext)):
            push(pt, ord(plaintext[i]))
    else:
        pt = plaintext
    let out = []
    let bc = counter
    let off = 0
    while off < len(pt):
        let ks = chacha20_block(key, bc, nonce)
        bc = bc + 1
        let lim = 64
        if off + lim > len(pt):
            lim = len(pt) - off
        for i in range(lim):
            push(out, pt[off + i] ^ ks[i])
        off = off + 64
    return out
