# SMP RTOS Scheduler
# ==================
# Pure-Sage preemptive task scheduler for SMP

gc_disable()

# ============================================================================
# Configuration
# ============================================================================

let RTOS_MAX_TASKS = 16
let RTOS_MAX_PRIORITY = 8
let RTOS_STACK_SIZE = 4096

# ============================================================================
# Task States
# ============================================================================

let TASK_READY = 0
let TASK_RUNNING = 1
let TASK_SLEEPING = 2
let TASK_BLOCKED = 3
let TASK_SUSPENDED = 4

# ============================================================================
# RTOS State
# ============================================================================

let rtos_tasks = []
let rtos_task_count = 0
let rtos_current_task = 0
let rtos_tick_count = 0
let rtos_running = false

# ============================================================================
# Initialization
# ============================================================================

proc rtos_init():
    rtos_tasks = []
    rtos_task_count = 0
    rtos_current_task = 0
    rtos_tick_count = 0
    rtos_running = true
    print("SageRTOS: scheduler initialized (" + str(RTOS_MAX_TASKS) + " tasks, " + str(RTOS_MAX_PRIORITY) + " priorities)")

# ============================================================================
# Task Creation
# ============================================================================

proc rtos_task_create(name, entry_func, priority, stack_size):
    if rtos_task_count >= RTOS_MAX_TASKS:
        return -1
    if priority >= RTOS_MAX_PRIORITY:
        priority = RTOS_MAX_PRIORITY - 1
    
    let tcb = {}
    tcb["name"] = name
    tcb["entry"] = entry_func
    tcb["priority"] = priority
    tcb["state"] = TASK_READY
    tcb["stack_size"] = stack_size
    tcb["sleep_until"] = 0
    tcb["id"] = rtos_task_count
    
    push(rtos_tasks, tcb)
    rtos_task_count = rtos_task_count + 1
    return tcb["id"]

# ============================================================================
# Scheduler
# ============================================================================

proc rtos_schedule():
    let prio = RTOS_MAX_PRIORITY - 1
    while prio >= 0:
        let i = (rtos_current_task + 1) % rtos_task_count
        let start = i
        while true:
            let t = rtos_tasks[i]
            if t != nil:
                if t["state"] == TASK_READY and t["priority"] == prio:
                    rtos_current_task = i
                    return i
                if t["state"] == TASK_SLEEPING:
                    if rtos_tick_count >= t["sleep_until"]:
                        t["state"] = TASK_READY
            i = (i + 1) % rtos_task_count
            if i == start:
                break
        prio = prio - 1
    return -1

proc rtos_run():
    print("SageRTOS: starting scheduler (" + str(rtos_task_count) + " tasks)")
    
    while rtos_running and rtos_task_count > 0:
        rtos_tick_count = rtos_tick_count + 1
        
        # Wake sleeping tasks
        let i = 0
        while i < rtos_task_count:
            let t = rtos_tasks[i]
            if t != nil and t["state"] == TASK_SLEEPING:
                if rtos_tick_count >= t["sleep_until"]:
                    t["state"] = TASK_READY
            i = i + 1
        
        # Find next ready task
        let task_id = rtos_schedule()
        if task_id < 0:
            rtos_idle()
            continue
        
        let task = rtos_tasks[task_id]
        if task == nil:
            continue
        
        task["state"] = TASK_RUNNING
        task["entry"]()
        if task["state"] == TASK_RUNNING:
            task["state"] = TASK_READY

proc rtos_idle():
    pass

# ============================================================================
# Task Control API
# ============================================================================

proc rtos_yield():
    let task = rtos_tasks[rtos_current_task]
    if task != nil:
        task["state"] = TASK_READY

proc rtos_sleep(ticks):
    let task = rtos_tasks[rtos_current_task]
    if task != nil:
        task["state"] = TASK_SLEEPING
        task["sleep_until"] = rtos_tick_count + ticks

proc rtos_suspend(task_id):
    let task = rtos_tasks[task_id]
    if task != nil:
        task["state"] = TASK_SUSPENDED

proc rtos_resume(task_id):
    let task = rtos_tasks[task_id]
    if task != nil and task["state"] == TASK_SUSPENDED:
        task["state"] = TASK_READY

proc rtos_notify(task_id):
    let task = rtos_tasks[task_id]
    if task != nil and task["state"] == TASK_SLEEPING:
        task["sleep_until"] = 0
        task["state"] = TASK_READY

proc rtos_halt():
    rtos_running = false

# ============================================================================
# Queue API
# ============================================================================

proc rtos_queue_create():
    return []

proc rtos_queue_send(q, item):
    push(q, item)

proc rtos_queue_recv(q):
    if len(q) == 0:
        return nil
    let item = q[0]
    let new_q = []
    for i in range(len(q) - 1):
        push(new_q, q[i + 1])
    q = new_q
    return item

# ============================================================================
# Mutex API
# ============================================================================

proc rtos_mutex_create():
    return {"locked": false, "owner": -1}

proc rtos_mutex_lock(mtx):
    while mtx["locked"]:
        rtos_yield()
    mtx["locked"] = true
    mtx["owner"] = rtos_current_task

proc rtos_mutex_unlock(mtx):
    mtx["locked"] = false
    mtx["owner"] = -1

# ============================================================================
# Info API
# ============================================================================

proc rtos_get_tick():
    return rtos_tick_count

proc rtos_get_task_count():
    return rtos_task_count

proc rtos_task_info(task_id):
    let task = rtos_tasks[task_id]
    if task == nil:
        return nil
    let states = ["READY", "RUNNING", "SLEEPING", "BLOCKED", "SUSPENDED"]
    return {
        "name": task["name"],
        "state": states[task["state"]],
        "prio": task["priority"],
        "ticks": task["sleep_until"]
    }

proc rtos_print_tasks():
    print("SageRTOS Task List:")
    let i = 0
    while i < rtos_task_count:
        let info = rtos_task_info(i)
        if info != nil:
            print("  [" + str(i) + "] " + info["name"] + " state=" + info["state"] + " prio=" + str(info["prio"]))
        i = i + 1