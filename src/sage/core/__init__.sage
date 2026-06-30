# SageSMP - Pure Sage Multicore Protocol
# =====================================
# A modular, mailbox-based protocol for multicore message passing

# Protocol version
let SMP_VERSION = "1.0.0"
let SMP_VERSION_MAJOR = 1
let SMP_VERSION_MINOR = 0
let SMP_VERSION_PATCH = 0

# Protocol opcodes
let SMP_OP_HEARTBEAT = 0
let SMP_OP_MESSAGE = 1
let SMP_OP_JOIN = 2
let SMP_OP_LEAVE = 3
let SMP_OP_MAILBOX = 4
let SMP_OP_MAILBOX_ACK = 5
let SMP_OP_SYNC = 6
let SMP_OP_SYNC_ACK = 7
let SMP_OP_BROADCAST = 8
let SMP_OP_NODE_INFO = 9

# Node states
let NODE_STATE_DISCONNECTED = 0
let NODE_STATE_CONNECTING = 1
let NODE_STATE_CONNECTED = 2
let NODE_STATE_READY = 3
let NODE_STATE_ERROR = 4

# Message types
let MSG_TYPE_DATA = 0
let MSG_TYPE_CONTROL = 1
let MSG_TYPE_ACK = 2
let MSG_TYPE_ERROR = 3

# Default configuration
let DEFAULT_HOST = "127.0.0.1"
let DEFAULT_PORT = 42000
let DEFAULT_TIMEOUT_MS = 5000
let DEFAULT_MAX_NODES = 64
let DEFAULT_MAILBOX_SIZE = 1024