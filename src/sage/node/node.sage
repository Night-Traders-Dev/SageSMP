# SMP Node Management
# ==================
# Node registration, discovery, and lifecycle management

gc_disable()

from smp.core import NODE_STATE_DISCONNECTED, NODE_STATE_CONNECTING, NODE_STATE_CONNECTED, NODE_STATE_READY, NODE_STATE_ERROR, DEFAULT_MAX_NODES

# ============================================================================
# Node Identity
# ============================================================================

proc generate_node_id():
    # Simple node ID generation based on timestamp and random component
    let ts = str(clock())
    let hash_part = str(hash(ts) % 1000000)
    # Pad with zeros if needed
    while len(hash_part) < 6:
        hash_part = "0" + hash_part
    return hash(ts) % 10000000

proc create_node(id, name, host, port):
    let node = {}
    node["id"] = id
    node["name"] = name
    node["host"] = host
    node["port"] = port
    node["state"] = NODE_STATE_DISCONNECTED
    node["mailbox"] = nil
    node["last_seen"] = 0
    node["capabilities"] = []
    node["metadata"] = {}
    node["connection"] = nil
    return node

# ============================================================================
# Node Registry
# ============================================================================

proc create_registry():
    let reg = {}
    reg["nodes"] = {}
    reg["by_name"] = {}
    reg["by_addr"] = {}
    reg["local_node"] = nil
    reg["next_id"] = generate_node_id()
    reg["max_nodes"] = DEFAULT_MAX_NODES
    return reg

proc register(registry, node):
    if len(dict_keys(registry["nodes"])) >= registry["max_nodes"]:
        raise "registry full: max nodes reached"
    
    registry["nodes"][str(node["id"])] = node
    if node["name"] != nil and node["name"] != "":
        registry["by_name"][node["name"]] = node
    if node["host"] != nil and node["port"] != nil:
        registry["by_addr"][node["host"] + ":" + str(node["port"])] = node
    return node["id"]

proc unregister(registry, node_id):
    if dict_has(registry["nodes"], str(node_id)):
        let node = registry["nodes"][str(node_id)]
        if node["name"] != nil and dict_has(registry["by_name"], node["name"]):
            dict_delete(registry["by_name"], node["name"])
        if node["host"] != nil and node["port"] != nil:
            dict_delete(registry["by_addr"], node["host"] + ":" + str(node["port"]))
        dict_delete(registry["nodes"], str(node_id))
        return true
    return false

proc get_node_by_id(registry, node_id):
    if dict_has(registry["nodes"], str(node_id)):
        return registry["nodes"][str(node_id)]
    return nil

proc get_node_by_name(registry, name):
    if dict_has(registry["by_name"], name):
        return registry["by_name"][name]
    return nil

proc get_node_by_addr(registry, host, port):
    let key = host + ":" + str(port)
    if dict_has(registry["by_addr"], key):
        return registry["by_addr"][key]
    return nil

# ============================================================================
# Node Lifecycle
# ============================================================================

proc connect(registry, node):
    node["state"] = NODE_STATE_CONNECTING
    node["last_seen"] = clock()
    return node

proc connected(registry, node):
    node["state"] = NODE_STATE_CONNECTED
    node["last_seen"] = clock()
    return node

proc ready(registry, node):
    node["state"] = NODE_STATE_READY
    node["last_seen"] = clock()
    return node

proc disconnect(registry, node):
    node["state"] = NODE_STATE_DISCONNECTED
    if node["mailbox"] != nil:
        # Close mailbox on disconnect
        if dict_has(node["mailbox"], "close"):
            node["mailbox"].close()
    return node

proc error(registry, node, err_msg):
    node["state"] = NODE_STATE_ERROR
    node["metadata"]["error"] = err_msg
    node["last_seen"] = clock()
    return node

proc update_last_seen(node):
    node["last_seen"] = clock()

proc is_node_connected(node):
    return node["state"] == NODE_STATE_CONNECTED or node["state"] == NODE_STATE_READY

proc is_node_ready(node):
    return node["state"] == NODE_STATE_READY

# ============================================================================
# Node Capabilities
# ============================================================================

proc add_capability(node, cap):
    push(node["capabilities"], cap)

proc remove_capability(node, cap):
    let idx = -1
    for i in range(len(node["capabilities"])):
        if node["capabilities"][i] == cap:
            idx = i
            break
    if idx >= 0:
        let new_caps = []
        for i in range(len(node["capabilities"])):
            if i != idx:
                push(new_caps, node["capabilities"][i])
        node["capabilities"] = new_caps
        return true
    return false

proc has_capability(node, cap):
    for i in range(len(node["capabilities"])):
        if node["capabilities"][i] == cap:
            return true
    return false

# ============================================================================
# Node Discovery
# ============================================================================

proc list_nodes(registry):
    return dict_keys(registry["nodes"])

proc list_connected(registry):
    let connected = []
    let ids = list_nodes(registry)
    for i in range(len(ids)):
        let node = registry["nodes"][ids[i]]
        if is_node_connected(node):
            push(connected, node)
    return connected

proc list_ready(registry):
    let ready_nodes = []
    let ids = list_nodes(registry)
    for i in range(len(ids)):
        let node = registry["nodes"][ids[i]]
        if is_node_ready(node):
            push(ready_nodes, node)
    return ready_nodes

proc count_nodes(registry):
    return len(dict_keys(registry["nodes"]))

proc count_connected(registry):
    return len(list_connected(registry))

proc count_ready(registry):
    return len(list_ready(registry))

# ============================================================================
# Local Node Setup
# ============================================================================

proc create_local_node(name, host, port):
    let registry = create_registry()
    let id = registry["next_id"]
    registry["next_id"] = registry["next_id"] + 1
    
    let node = create_node(id, name, host, port)
    registry["local_node"] = node
    add_capability(node, "mailbox")
    add_capability(node, "multicore")
    
    register(registry, node)
    return [registry, node]

proc set_local_node(registry, node):
    registry["local_node"] = node
    add_capability(node, "mailbox")
    add_capability(node, "multicore")
    register(registry, node)

proc get_local_node(registry):
    return registry["local_node"]