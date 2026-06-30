# RTOS Module

Pure-Sage RTOS scheduler for SMP with GC-aware scheduling.

## Overview

The RTOS module provides a preemptive task scheduler with priority-based scheduling and periodic garbage collection. Designed for real-time SMP applications.

## Configuration

| Constant | Value | Description |
|----------|-------|-------------|
| `RTOS_MAX_TASKS` | 16 | Maximum concurrent tasks |
| `RTOS_MAX_PRIORITY` | 8 | Priority levels (0=highest) |
| `RTOS_STACK_SIZE` | 4096 | Task stack size |
| `RTOS_GC_INTERVAL` | 100 | GC runs every N ticks |

## Task States

| State | Constant | Description |
|-------|----------|-------------|
| `TASK_READY` (0) | - | Ready to run |
| `TASK_RUNNING` (1) | - | Currently executing |
| `TASK_SLEEPING` (2) | - | Sleeping until wake tick |
| `TASK_BLOCKED` (3) | - | Blocked waiting for resource |
| `TASK_SUSPENDED` (4) | - | Suspended indefinitely |

## Task Management

```sage
proc rtos_init()
```
Initialize RTOS scheduler state.

```sage
proc rtos_task_create(name, entry_func, priority, stack_size) -> task_id
```
Create task. Returns task ID or -1 if full.

```sage
proc rtos_task_info(task_id) -> {"name", "state", "prio", "ticks"}
```
Get task information.

```sage
proc rtos_get_task_count() -> int
proc rtos_get_tick() -> int
```

## Task Control

```sage
proc rtos_yield()
```
Yield current task, return to READY state.

```sage
proc rtos_sleep(ticks)
```
Sleep for specified ticks.

```sage
proc rtos_suspend(task_id)
proc rtos_resume(task_id)
proc rtos_notify(task_id)
proc rtos_halt()
```

## Synchronization

```sage
proc rtos_queue_create() -> queue
proc rtos_queue_send(q, item)
proc rtos_queue_recv(q) -> item_or_nil

proc rtos_mutex_create() -> mutex
proc rtos_mutex_lock(mtx)
proc rtos_mutex_unlock(mtx)
```

## Memory Management

```sage
proc rtos_alloc_obj(obj) -> obj
```
Allocate object in RTOS memory pool.

```sage
proc rtos_free_obj(obj)
```
Free object from pool.

```sage
proc rtos_gc_collect() -> objects_freed
```
Run GC on RTOS memory pool. Called automatically every `RTOS_GC_INTERVAL` ticks.

## Scheduler

```sage
proc rtos_schedule() -> task_id
```
Select next ready task by priority.

```sage
proc rtos_run()
```
Run scheduler main loop.

```sage
proc rtos_idle()
```
Idle task (does nothing).

```sage
proc rtos_print_tasks()
```
Print all task states.

## Usage Example

```sage
import smp.rtos

rtos_init()

# Create tasks
rtos_task_create("high", proc():
    print("High priority running")
, 2, 1024)

rtos_task_create("low", proc():
    print("Low priority running")
, 0, 1024)

rtos_task_create("medium", proc():
    for i in range(3):
        print("Medium priority tick " + str(i))
, 1, 1024)

# Run scheduler
rtos_run()
```

### Build Configuration

For OTP-enabled RTOS, create `.smp_config`:

```json
{
  "enable_rtos": true,
  "relay_port": 42000
}
```

Build with:
```bash
./sagemake --init-config
./sagemake src/sage/rtos/rtos
```