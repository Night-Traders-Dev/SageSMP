proc to_byte_list(data):
    if type(data) == "string" or type(data) == "str":
        let bytes = []
        for i in range(len(data)):
            push(bytes, ord(data[i]))
        return bytes
    return data

proc clamp(p):
    let priv = to_byte_list(p)
    if len(priv) >= 32:
        priv[0] = priv[0] & 248
        priv[31] = priv[31] & 127
        priv[31] = priv[31] | 64
    return priv

let p = [237, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 127]

proc cmp(a, b):
    let i = 31
    while i >= 0:
        if a[i] > b[i]:
            return 1
        if a[i] < b[i]:
            return -1
        i = i - 1
    return 0

proc add_mod(a, b):
    let carry = 0
    let r = []
    for i in range(32):
        let s = a[i] + b[i] + carry
        push(r, s & 255)
        carry = s >> 8

    if carry > 0:
        r[0] = r[0] + 38
        carry = r[0] >> 8
        r[0] = r[0] & 255
        for i in range(1, 32):
            let s = r[i] + carry
            r[i] = s & 255
            carry = s >> 8
        while carry > 0:
            r[0] = r[0] + carry * 38
            carry = r[0] >> 8
            r[0] = r[0] & 255
            for i in range(1, 32):
                let s = r[i] + carry
                r[i] = s & 255
                carry = s >> 8

    while cmp(r, p) >= 0:
        let borrow = 0
        for i in range(32):
            let d = r[i] - p[i] - borrow
            if d < 0:
                d = d + 256
                borrow = 1
            else:
                borrow = 0
            r[i] = d

    return r

proc sub_mod(a, b):
    let borrow = 0
    let r = []
    for i in range(32):
        let d = a[i] - b[i] - borrow
        if d < 0:
            d = d + 256
            borrow = 1
        else:
            borrow = 0
        push(r, d)

    if borrow:
        let carry = 0
        for i in range(32):
            let s = r[i] + p[i] + carry
            r[i] = s & 255
            carry = s >> 8

    while cmp(r, p) >= 0:
        let borrow = 0
        for i in range(32):
            let d = r[i] - p[i] - borrow
            if d < 0:
                d = d + 256
                borrow = 1
            else:
                borrow = 0
            r[i] = d

    return r

proc mul_mod(a, b):
    let prod = []
    for i in range(64):
        push(prod, 0)

    for i in range(32):
        if a[i] == 0:
            continue
        for j in range(32):
            if b[j] == 0:
                continue
            let v = a[i] * b[j]
            prod[i+j] = prod[i+j] + (v & 255)
            prod[i+j+1] = prod[i+j+1] + (v >> 8)

    let carry = 0
    for i in range(64):
        let s = prod[i] + carry
        prod[i] = s & 255
        carry = s >> 8

    let r = []
    for i in range(32):
        push(r, prod[i])

    for i in range(32):
        r[i] = r[i] + prod[32+i] * 38

    carry = 0
    for i in range(32):
        let s = r[i] + carry
        r[i] = s & 255
        carry = s >> 8

    while carry > 0:
        let s = r[0] + carry * 38
        r[0] = s & 255
        carry = s >> 8
        let i = 1
        while i < 32 and carry > 0:
            let s = r[i] + carry
            r[i] = s & 255
            carry = s >> 8
            i = i + 1

    while cmp(r, p) >= 0:
        let borrow = 0
        for i in range(32):
            let d = r[i] - p[i] - borrow
            if d < 0:
                d = d + 256
                borrow = 1
            else:
                borrow = 0
            r[i] = d

    return r

proc pow_mod(x, e):
    let r = []
    for i in range(32):
        push(r, 0)
    r[0] = 1
    let b = x
    for ei in range(32):
        let byteval = e[ei]
        for bit in range(8):
            if byteval & 1:
                r = mul_mod(r, b)
            byteval = byteval >> 1
            if ei * 8 + bit + 1 < 255:
                b = mul_mod(b, b)
    return r

proc inv_mod(x):
    let e = []
    for i in range(32):
        push(e, p[i])
    e[0] = e[0] - 2
    return pow_mod(x, e)

proc x25519(private, base):
    let priv = clamp(private)
    let u = to_byte_list(base)

    let x1 = []
    let x2 = []
    let z2 = []
    let x3 = []
    let z3 = []
    for i in range(32):
        push(x1, u[i])
        push(x2, 0)
        push(z2, 0)
        push(x3, u[i])
        push(z3, 0)
    x2[0] = 1
    z3[0] = 1

    let swap = 0

    let t = 254
    while t >= 0:
        let byte_idx = t >> 3
        let bit_idx = t & 7
        let bit = (priv[byte_idx] >> bit_idx) & 1
        swap = swap ^ bit

        if swap:
            for i in range(32):
                let tmp = x2[i]
                x2[i] = x3[i]
                x3[i] = tmp
                tmp = z2[i]
                z2[i] = z3[i]
                z3[i] = tmp

        swap = bit

        let a = add_mod(x2, z2)
        let aa = mul_mod(a, a)
        let b = sub_mod(x2, z2)
        let bb = mul_mod(b, b)
        let e = sub_mod(aa, bb)
        let c = add_mod(x3, z3)
        let d = sub_mod(x3, z3)
        let da = mul_mod(d, a)
        let cb = mul_mod(c, b)

        let da_cb = add_mod(da, cb)
        x3 = mul_mod(da_cb, da_cb)

        let da_cb2 = sub_mod(da, cb)
        let tmp = mul_mod(da_cb2, da_cb2)
        z3 = mul_mod(x1, tmp)

        x2 = mul_mod(aa, bb)

        let a24 = [121665, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        let a24e = mul_mod(a24, e)
        let aa_a24e = add_mod(aa, a24e)
        z2 = mul_mod(e, aa_a24e)

        t = t - 1

    if swap:
        for i in range(32):
            let tmp = x2[i]
            x2[i] = x3[i]
            x3[i] = tmp
            tmp = z2[i]
            z2[i] = z3[i]
            z3[i] = tmp

    let result = mul_mod(x2, inv_mod(z2))
    return result
