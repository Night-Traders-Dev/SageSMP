# Demo Module

Runnable demos demonstrating SageSMP functionality.

## Overview

The demo module provides executable demonstrations of SageSMP capabilities. These files compile to ELF binaries using `sage --compile`.

## Files

### demo.sage

Main demo showcasing:
- **Mailbox**: FIFO message queuing with statistics tracking
- **Node Registry**: Node discovery and capability management
- **RTOS**: Priority-based scheduling with periodic GC cleanup

Run with:
```bash
./sagemake --demo
./bin/demo_smp
```

Output demonstrates:
```
=== SageSMP Mailbox Demo ===
Sending messages...
  Sent 5 messages
Processing messages...
  Handler: Received message #1: Message 1
  ...

=== SageSMP Node Registry Demo ===
Registered 3 nodes:
  - worker-1 (compute, storage)
  ...

=== SageSMP RTOS Scheduler Demo ===
Creating 3 tasks...
Task count: 3
Running scheduler with GC-aware cleanup (every 5 ticks)...
  Task 1 running (priority 2, run 1/3)
  ...
```

### example.sage

Usage examples and test suite for development.

Run with:
```bash
./sagemake --test
# or
sage src/sage/demo/example.sage
```

## Running Demos

```bash
# Build all demos
./sagemake --all

# Run specific demo
./bin/demo_smp
./bin/relay
./bin/client_shell
./bin/secure_msg
```

## OTP Encryption Demo

```bash
./sagemake --secure
./bin/secure_msg_demo
```

Shows end-to-end OTP encryption:
- Message encrypted with OTP-derived key
- Signed with hash-based signature
- Decrypted and verified on receive