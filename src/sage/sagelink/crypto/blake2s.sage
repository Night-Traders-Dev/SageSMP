proc u32(x):
    return x & 4294967295

proc rotr32(x, n):
    if n == 0:
        return u32(x)
    let bottom_n = x & ((1 << n) - 1)
    let top_part = bottom_n << (32 - n)
    let top_bits = x >> n
    if x >= 0x80000000:
        let m = (1 << (32 - n)) - 1
        top_bits = top_bits & m
    return u32(top_part | top_bits)

proc le_bytes_to_u32(b, off):
    return b[off] | (b[off+1] << 8) | (b[off+2] << 16) | (b[off+3] << 24)

proc u32_to_le(v):
    let b = []
    for i in range(4):
        push(b, (v >> (8 * i)) & 255)
    return b

proc to_byte_list(data):
    if type(data) == "string" or type(data) == "str":
        let bytes = []
        for i in range(len(data)):
            push(bytes, ord(data[i]))
        return bytes
    return data

let sigma = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0]
]

let blake2s_iv = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
]

proc g(v, a, b, c, d, x, y):
    v[a] = u32(v[a] + v[b] + x)
    v[d] = rotr32(u32(v[d] ^ v[a]), 16)
    v[c] = u32(v[c] + v[d])
    v[b] = rotr32(u32(v[b] ^ v[c]), 12)
    v[a] = u32(v[a] + v[b] + y)
    v[d] = rotr32(u32(v[d] ^ v[a]), 8)
    v[c] = u32(v[c] + v[d])
    v[b] = rotr32(u32(v[b] ^ v[c]), 7)

proc blake2s_compress(h, block, counter, is_last):
    let m = []
    for i in range(16):
        push(m, le_bytes_to_u32(block, i * 4))

    let v = []
    for i in range(8):
        push(v, h[i])
    for i in range(8):
        push(v, blake2s_iv[i])
    v[12] = u32(v[12] ^ (counter & 4294967295))
    v[13] = u32(v[13] ^ ((counter >> 32) & 4294967295))
    if is_last:
        v[14] = u32(v[14] ^ 4294967295)

    for r in range(10):
        let s = sigma[r]
        g(v, 0, 4, 8, 12, m[s[0]], m[s[1]])
        g(v, 1, 5, 9, 13, m[s[2]], m[s[3]])
        g(v, 2, 6, 10, 14, m[s[4]], m[s[5]])
        g(v, 3, 7, 11, 15, m[s[6]], m[s[7]])
        g(v, 0, 5, 10, 15, m[s[8]], m[s[9]])
        g(v, 1, 6, 11, 12, m[s[10]], m[s[11]])
        g(v, 2, 7, 8, 13, m[s[12]], m[s[13]])
        g(v, 3, 4, 9, 14, m[s[14]], m[s[15]])

    for i in range(8):
        h[i] = u32(h[i] ^ v[i] ^ v[i + 8])

proc blake2s(data, key=nil):
    let msg = to_byte_list(data)
    let key_bytes = []
    if key != nil:
        key_bytes = to_byte_list(key)
    let klen = len(key_bytes)
    let outlen = 32

    let h = []
    for i in range(8):
        push(h, blake2s_iv[i])
    h[0] = u32(h[0] ^ 0x01010000)
    h[0] = u32(h[0] ^ (klen << 8))
    h[0] = u32(h[0] ^ outlen)

    let buf = []
    for i in range(64):
        push(buf, 0)

    if klen > 0:
        for i in range(64):
            if i < klen:
                buf[i] = key_bytes[i]
            else:
                buf[i] = 0
        blake2s_compress(h, buf, 0, false)

    let total = len(msg)
    let off = 0
    while off < total:
        let remaining = total - off
        let blk = 64
        if remaining < 64:
            blk = remaining
        for i in range(64):
            if i < blk:
                buf[i] = msg[off + i]
            else:
                buf[i] = 0
        off = off + blk
        let last = (off >= total)
        blake2s_compress(h, buf, off, last)

    let out = []
    for i in range(8):
        let le = u32_to_le(h[i])
        for j in range(4):
            push(out, le[j])
    return out
