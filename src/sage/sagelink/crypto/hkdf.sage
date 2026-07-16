import crypto.blake2s as blake2s

proc hkdf_extract(salt, ikm):
    if type(salt) == "string":
        let salt_bytes = []
        for i in range(len(salt)):
            push(salt_bytes, ord(salt[i]))
        salt = salt_bytes
    if type(ikm) == "string":
        let ikm_bytes = []
        for i in range(len(ikm)):
            push(ikm_bytes, ord(ikm[i]))
        ikm = ikm_bytes
    let input_data = []
    for i in range(len(salt)):
        push(input_data, salt[i])
    for i in range(len(ikm)):
        push(input_data, ikm[i])
    return blake2s.blake2s(input_data)

proc hkdf_expand(prk, info, length):
    let info_bytes = []
    if type(info) == "string":
        for i in range(len(info)):
            push(info_bytes, ord(info[i]))
    else:
        info_bytes = info
    let okm = []
    let t = []
    let n = (length + 31) / 32
    for i in range(n):
        let counter = i + 1
        let input_data = []
        for j in range(len(t)):
            push(input_data, t[j])
        for j in range(len(info_bytes)):
            push(input_data, info_bytes[j])
        push(input_data, counter)
        t = blake2s.blake2s(input_data)
        for j in range(len(t)):
            if len(okm) < length:
                push(okm, t[j])
    return okm
