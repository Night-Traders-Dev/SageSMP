# Core Module

Core definitions, constants, and protocol opcodes for SageSMP.

## Overview

The core module provides the foundational constants and configuration values used throughout the SageSMP protocol. It defines protocol opcodes, node states, message types, and default settings.

## Constants

### Protocol Version
- `SMP_VERSION` - Semantic version string (e.g., "1.0.0")
- `SMP_VERSION_MAJOR` - Major version number (1)
- `SMP_VERSION_MINOR` - Minor version number (0)
- `SMP_VERSION_PATCH` - Patch version number (0)

### Protocol Opcodes
| Opcode | Constant | Description |
|--------|----------|-------------|
| 0 | `SMP_OP_HEARTBEAT` | Keep-alive ping |
| 1 | `SMP_OP_MESSAGE` | Data message between nodes |
| 2 | `SMP_OP_JOIN` | Node join notification |
| 3 | `SMP_OP_LEAVE` | Node leave notification |
| 4 | `SMP_OP_MAILBOX` | Direct mailbox transfer |
| 5 | `SMP_OP_MAILBOX_ACK` | Mailbox operation acknowledgment |
| 6 | `SMP_OP_SYNC` | State synchronization |
| 7 | `SMP_OP_SYNC_ACK` | Sync acknowledgment |
| 8 | `SMP_OP_BROADCAST` | Broadcast to all nodes |
| 9 | `SMP_OP_NODE_INFO` | Node metadata exchange |

### Node States
| State | Constant | Description |
|-------|----------|-------------|
| 0 | `NODE_STATE_DISCONNECTED` | Node not connected |
| 1 | `NODE_STATE_CONNECTING` | Connection in progress |
| 2 | `NODE_STATE_CONNECTED` | TCP connected |
| 3 | `NODE_STATE_READY` | Ready for messaging |
| 4 | `NODE_STATE_ERROR` | Error state |

### Message Types
| Type | Constant | Description |
|------|----------|-------------|
| 0 | `MSG_TYPE_DATA` | Application data |
| 1 | `MSG_TYPE_CONTROL` | Control message |
| 2 | `MSG_TYPE_ACK` | Acknowledgment |
| 3 | `MSG_TYPE_ERROR` | Error message |

### Default Configuration
- `DEFAULT_HOST` - Default bind host ("127.0.0.1")
- `DEFAULT_PORT` - Default port (42000)
- `DEFAULT_TIMEOUT_MS` - Default timeout in milliseconds (5000)
- `DEFAULT_MAX_NODES` - Maximum nodes in registry (64)
- `DEFAULT_MAILBOX_SIZE` - Default mailbox capacity (1024)

## Usage

```sage
import smp.core

# Check protocol version
print "SMP Version: " + SMP_VERSION

# Use opcodes
if msg["opcode"] == SMP_OP_MESSAGE:
    handle_message(msg)
```