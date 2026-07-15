let DQ = chr(34)

proc json_escape(s):
    let r = replace(s, chr(92), chr(92) + chr(92))
    r = replace(r, chr(34), chr(92) + chr(34))
    r = replace(r, chr(10), chr(92) + "n")
    r = replace(r, chr(9), chr(92) + "t")
    r = replace(r, chr(13), chr(92) + "r")
    return r

proc json_encode(val):
    let t = type(val)
    if t == "nil":
        return "null"
    if t == "number":
        return str(val)
    if t == "string":
        return DQ + json_escape(val) + DQ
    if t == "array":
        let parts = ["["]
        for i in range(len(val)):
            if i > 0: push(parts, ",")
            push(parts, json_encode(val[i]))
        push(parts, "]")
        return join(parts, "")
    if t == "dict":
        let parts = ["{"]
        let keys = dict_keys(val)
        for i in range(len(keys)):
            if i > 0: push(parts, ",")
            push(parts, DQ + keys[i] + DQ + ":")
            push(parts, json_encode(val[keys[i]]))
        push(parts, "}")
        return join(parts, "")
    return DQ + json_escape(str(val)) + DQ

proc json_skip_ws(raw, i, n):
    while i < n and (raw[i] == " " or raw[i] == chr(10) or raw[i] == chr(13) or raw[i] == chr(9)):
        i = i + 1
    end
    return i

proc json_parse_value(raw, i, n):
    i = json_skip_ws(raw, i, n)
    if i >= n:
        return {"value": nil, "next": i}
    end
    let c = raw[i]
    if c == "{":
        let obj = {}
        i = i + 1
        i = json_skip_ws(raw, i, n)
        if i < n and raw[i] == "}":
            return {"value": obj, "next": i + 1}
        end
        while i < n:
            i = json_skip_ws(raw, i, n)
            if i >= n or raw[i] == "}":
                break
            end
            if raw[i] != DQ:
                return {"value": nil, "next": i}
            end
            i = i + 1
            let key = ""
            while i < n and raw[i] != DQ:
                if raw[i] == chr(92):
                    i = i + 1
                end
                key = key + raw[i]
                i = i + 1
            end
            i = i + 1
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ":":
                i = i + 1
            end
            let res = json_parse_value(raw, i, n)
            obj[key] = res["value"]
            i = res["next"]
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ",":
                i = i + 1
            end
        end
        if i < n and raw[i] == "}":
            i = i + 1
        end
        return {"value": obj, "next": i}
    elif c == "[":
        let arr = []
        i = i + 1
        i = json_skip_ws(raw, i, n)
        if i < n and raw[i] == "]":
            return {"value": arr, "next": i + 1}
        end
        while i < n:
            i = json_skip_ws(raw, i, n)
            if i >= n or raw[i] == "]":
                break
            end
            let res = json_parse_value(raw, i, n)
            push(arr, res["value"])
            i = res["next"]
            i = json_skip_ws(raw, i, n)
            while i < n and raw[i] == ",":
                i = i + 1
            end
        end
        if i < n and raw[i] == "]":
            i = i + 1
        end
        return {"value": arr, "next": i}
    elif c == DQ:
        i = i + 1
        let s = ""
        while i < n and raw[i] != DQ:
            if raw[i] == chr(92):
                i = i + 1
                if i < n:
                    let ec = raw[i]
                    if ec == "n":
                        s = s + chr(10)
                    elif ec == "t":
                        s = s + chr(9)
                    elif ec == "r":
                        s = s + chr(13)
                    else:
                        s = s + chr(92) + ec
                    end
                    i = i + 1
                end
            else:
                s = s + raw[i]
                i = i + 1
            end
        end
        if i < n and raw[i] == DQ:
            i = i + 1
        end
        return {"value": s, "next": i}
    elif c == "t":
        return {"value": 1, "next": i + 4}
    elif c == "f":
        return {"value": 0, "next": i + 5}
    elif c == "n":
        return {"value": nil, "next": i + 4}
    else:
        let num_str = ""
        while i < n and ((raw[i] >= "0" and raw[i] <= "9") or raw[i] == "." or raw[i] == "-" or raw[i] == "+" or raw[i] == "e" or raw[i] == "E"):
            num_str = num_str + raw[i]
            i = i + 1
        end
        if len(num_str) > 0:
            return {"value": tonumber(num_str), "next": i}
        end
        return {"value": nil, "next": i}
    end

proc json_decode(raw):
    if raw == nil or len(raw) == 0:
        return nil
    end
    let n = len(raw)
    let res = json_parse_value(raw, 0, n)
    return res["value"]
