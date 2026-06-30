# SageSMP Demo
# ============
# Demonstrates a simple SMP cluster with GC-aware RTOS scheduling

gc_disable()

# ============================================================================
# Demo: Mailbox Operations
# ============================================================================

proc demo_mailbox():
    print("=== SageSMP Mailbox Demo ===")
    print("")
    
    # Create a simple mailbox (simulating what smp.mailbox.create_mailbox does)
    let mbox = {}
    mbox["buffer"] = []
    mbox["stats"] = {"sent": 0, "received": 0, "acked": 0}
    
    # Send some messages
    print("Sending messages...")
    for i in range(5):
        let msg = {"sender_id": 1, "recipient_id": 0, "type": 0, "payload": "Message " + str(i + 1), "seq": i + 1}
        push(mbox["buffer"], msg)
        mbox["stats"]["sent"] = mbox["stats"]["sent"] + 1
    print("  Sent 5 messages")
    print("")
    
    # Process messages (simulating mailbox handler)
    print("Processing messages...")
    let msg_count = 0
    while len(mbox["buffer"]) > 0:
        let msg = mbox["buffer"][0]
        let new_buf = []
        for j in range(len(mbox["buffer"]) - 1):
            push(new_buf, mbox["buffer"][j + 1])
        mbox["buffer"] = new_buf
        msg_count = msg_count + 1
        print("  Handler: Received message #" + str(msg_count) + ": " + str(msg["payload"]))
        mbox["stats"]["received"] = mbox["stats"]["received"] + 1
    print("")
    
    # Show statistics
    print("Mailbox stats:")
    print("  Sent: " + str(mbox["stats"]["sent"]))
    print("  Received: " + str(mbox["stats"]["received"]))
    print("  Acknowledged: " + str(mbox["stats"]["acked"]))
    print("")

# ============================================================================
# Demo: Node Registry
# ============================================================================

proc demo_node_registry():
    print("=== SageSMP Node Registry Demo ===")
    print("")
    
    let registry = {}
    registry["nodes"] = {}
    registry["by_name"] = {}
    
    # Create nodes
    let node1 = {"id": 1, "name": "worker-1", "host": "192.168.1.10", "port": 42001, "state": 3, "capabilities": ["compute", "storage"]}
    let node2 = {"id": 2, "name": "worker-2", "host": "192.168.1.11", "port": 42002, "state": 2, "capabilities": ["compute"]}
    let node3 = {"id": 3, "name": "coordinator", "host": "192.168.1.1", "port": 42000, "state": 3, "capabilities": ["coordinator"]}
    
    registry["nodes"]["1"] = node1
    registry["nodes"]["2"] = node2
    registry["nodes"]["3"] = node3
    registry["by_name"]["worker-1"] = node1
    registry["by_name"]["worker-2"] = node2
    registry["by_name"]["coordinator"] = node3
    
    print("Registered 3 nodes:")
    print("  - worker-1 (compute, storage)")
    print("  - worker-2 (compute)")
    print("  - coordinator (coordinator)")
    print("")
    
    print("Total nodes: " + str(len(dict_keys(registry["nodes"]))) + "\n")
    
    let found = registry["by_name"]["coordinator"]
    print("Found coordinator node:")
    print("  ID: " + str(found["id"]))
    print("  Host: " + found["host"] + ":" + str(found["port"]))
    print("")

# ============================================================================
# Demo: RTOS with GC Scheduling
# ============================================================================

proc demo_rtos():
    print("=== SageSMP RTOS Scheduler Demo ===")
    print("")
    
    # RTOS state
    let RTOS_GC_INTERVAL = 5
    
    let rtos_tasks = [{"name": "Task1", "priority": 2, "state": 0}, {"name": "Task2", "priority": 1, "state": 0}, {"name": "Task3", "priority": 0, "state": 0}]
    let rtos_tick_count = 0
    let rtos_memory_pool = []
    let task1_runs = 0
    let task2_runs = 0
    let task3_runs = 0
    
    print("Creating 3 tasks...")
    print("")
    print("Task count: " + str(len(rtos_tasks)) + "\n")
    
    print("Running scheduler with GC-aware cleanup (every 5 ticks)...")
    print("")
    
    # Simulate RTOS tick loop
    while rtos_tick_count < 10:
        rtos_tick_count = rtos_tick_count + 1
        
        # Periodic GC collection
        if rtos_tick_count % RTOS_GC_INTERVAL == 0:
            print("  [GC] Tick " + str(rtos_tick_count) + ": Collecting RTOS memory pool...")
            let before = len(rtos_memory_pool)
            rtos_memory_pool = []
            print("  [GC] Freed " + str(before) + " objects\n")
        
        # Execute tasks by priority (higher number = higher priority)
        if rtos_tasks[0]["priority"] == 2 and task1_runs < 3:
            task1_runs = task1_runs + 1
            print("  Task 1 running (priority 2, run " + str(task1_runs) + "/3)")
            push(rtos_memory_pool, {"data": "task1_output_" + str(task1_runs)})
        elif rtos_tasks[1]["priority"] == 1 and task2_runs < 2:
            task2_runs = task2_runs + 1
            print("  Task 2 running (priority 1)")
        elif rtos_tasks[2]["priority"] == 0 and task3_runs < 1:
            task3_runs = task3_runs + 1
            print("  Task 3 running (priority 0)")
    
    print("")
    print("Final: Task1=" + str(task1_runs) + " runs, Task2=" + str(task2_runs) + " runs, Task3=" + str(task3_runs) + " runs")
    print("")

# Run all demos
demo_mailbox()
demo_node_registry()
demo_rtos()
print("=== Demo Complete ===")
print("")
print("SageSMP modules demonstrated:")
print("  - Mailbox: Thread-safe message queues with acknowledgment")
print("  - Node Registry: Node discovery and capabilities management")
print("  - RTOS: Priority-based scheduling with periodic GC cleanup")
print("")