proc poly1305_mac(key, msg):
    let r = []
    for i in range(16):
        push(r, key[i])
    r[3] = r[3] & 15
    r[4] = r[4] & 252
    r[7] = r[7] & 15
    r[8] = r[8] & 252
    r[11] = r[11] & 15
    r[12] = r[12] & 252
    r[15] = r[15] & 15

    let s = []
    for i in range(16, 32):
        push(s, key[i])

    let m = []
    if type(msg) == "string":
        for i in range(len(msg)):
            push(m, ord(msg[i]))
    else:
        m = msg

    let acc = []
    for i in range(17):
        push(acc, 0)

    let off = 0
    while off < len(m):
        let remaining = len(m) - off
        let blk = 16
        if remaining < 16:
            blk = remaining

        let block = []
        for i in range(16):
            if off + i < len(m):
                push(block, m[off + i])
            else:
                push(block, 0)
        push(block, 0)
        block[blk] = 1

        let carry = 0
        for i in range(17):
            let sum = acc[i] + block[i] + carry
            acc[i] = sum & 255
            carry = sum >> 8

        let prod = []
        for i in range(33):
            push(prod, 0)
        for i in range(17):
            if acc[i] == 0:
                continue
            for j in range(16):
                let val = acc[i] * r[j]
                let idx = i + j
                prod[idx] = prod[idx] + (val & 255)
                prod[idx+1] = prod[idx+1] + (val >> 8)
        carry = 0
        for i in range(33):
            let sum = prod[i] + carry
            prod[i] = sum & 255
            carry = sum >> 8

        for i in range(17):
            acc[i] = 0

        carry = 0
        for i in range(16):
            let sum = prod[i] + carry
            acc[i] = sum & 255
            carry = sum >> 8
        acc[16] = prod[16] & 3

        let high = []
        for i in range(17):
            push(high, 0)
        high[0] = (prod[16] >> 2) | ((prod[17] & 3) << 6)
        for i in range(1, 16):
            high[i] = (prod[16 + i] >> 2) | ((prod[17 + i] & 3) << 6)
        high[16] = prod[32] >> 2

        let add = []
        for i in range(17):
            push(add, 0)
        carry = 0
        for i in range(17):
            let val = high[i] * 5 + carry
            add[i] = val & 255
            carry = val >> 8

        carry = 0
        for i in range(17):
            let sum = acc[i] + add[i] + carry
            acc[i] = sum & 255
            carry = sum >> 8

        if acc[16] >= 4:
            let extra = acc[16] >> 2
            let v = extra * 5
            acc[16] = acc[16] & 3
            let sum = acc[0] + v
            acc[0] = sum & 255
            carry = sum >> 8
            if carry > 0:
                let j = 1
                while carry > 0 and j < 17:
                    sum = acc[j] + carry
                    acc[j] = sum & 255
                    carry = sum >> 8
                    j = j + 1

        off = off + blk

    let mac = []
    let c = 0
    for i in range(16):
        let sum = acc[i] + s[i] + c
        push(mac, sum & 255)
        c = sum >> 8
    return mac
