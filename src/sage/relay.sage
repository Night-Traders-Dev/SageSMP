# SMP Relay Server
# ===============
# Configurable relay server with interactive shell

gc_disable()

# ============================================================================
# Relay Configuration
# ============================================================================

let relay_rules = []

proc add_relay_rule(trigger_msg, target_host, target_port, forward_msg):
    let rule = {}
    rule["trigger"] = trigger_msg
    rule["target_host"] = target_host
    rule["target_port"] = target_port
    rule["forward"] = forward_msg
    push(relay_rules, rule)
    return len(relay_rules) - 1

proc list_relay_rules():
    print("Relay Rules:")
    for i in range(len(relay_rules)):
        let r = relay_rules[i]
        print("  [" + str(i) + "] Trigger: '" + r["trigger"] + "' -> " + r["target_host"] + ":" + str(r["target_port"]))
    return relay_rules

proc relay_show_config(host, port):
    print("Relay Server Configuration:")
    print("  Host: " + host)
    print("  Port: " + str(port))
    print("  Active Rules: " + str(len(relay_rules)))

# ============================================================================
# Main entry point
# ============================================================================

proc run_relay_demo():
    print("=== SageSMP Relay Server Demo ===")
    print("")
    
    let host = "0.0.0.0"
    let port = 42000
    
    relay_show_config(host, port)
    print("")
    
    # Add demo rules
    print("Adding relay rules...")
    add_relay_rule("hello", "192.168.1.100", 42001, "Hello from relay!")
    add_relay_rule("status", "192.168.1.100", 42001, "Status OK")
    add_relay_rule("forward_test", "192.168.1.101", 42002, "Forwarded message")
    print("")
    
    list_relay_rules()
    print("")
    
    print("Simulating message processing:")
    let msgs = ["hello", "status", "forward_test", "unknown"]
    for i in range(len(msgs)):
        let msg = msgs[i]
        print "Received: " + msg
        let matched = false
        for j in range(len(relay_rules)):
            let rule = relay_rules[j]
            if msg == rule["trigger"]:
                print "  -> Relaying: " + rule["forward"] + " to " + rule["target_host"] + ":" + str(rule["target_port"])
                matched = true
                break
        if not matched:
            print "  -> No matching rule"
    
    print ""
    print "=== Demo Complete ==="

run_relay_demo()