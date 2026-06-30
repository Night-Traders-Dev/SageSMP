# Node Module

Node registration, discovery, and lifecycle management for SageSMP.

## Overview

The node module provides comprehensive node management including:
- Node identity and creation
- Node registry for tracking multiple nodes
- Node lifecycle state transitions
- Node capability management
- Node discovery and listing

## API Reference

### Node Identity

```sage
proc generate_node_id() -> node_id
```
Generate unique node ID based on timestamp and hash.

```sage
proc create_node(id, name, host, port) -> node
```
Create a node with specified properties:
- `id` - Unique identifier
- `name` - Human-readable name
- `host` - IP address
- `port` - Port number

Node structure includes:
- `id`, `name`, `host`, `port`
- `state` - Current node state
- `mailbox` - Associated mailbox
- `last_seen` - Timestamp
- `capabilities` - Array of capability strings
- `metadata` - Custom metadata dict
- `connection` - Connection reference

### Node Registry

```sage
proc create_registry() -> registry
```
Create node registry with:
- `nodes` - Dict of node_id -> node
- `by_name` - Dict of name -> node
- `by_addr` - Dict of host:port -> node
- `local_node` - Current node reference
- `next_id` - Next available ID
- `max_nodes` - Maximum nodes allowed

```sage
proc register(registry, node) -> node_id
```
Register node in registry. Raises error if at max capacity.

```sage
proc unregister(registry, node_id) -> bool
```
Remove node from registry.

```sage
proc get_node_by_id(registry, node_id) -> node_or_nil
```
Get node by ID.

```sage
proc get_node_by_name(registry, name) -> node_or_nil
```
Get node by name.

```sage
proc get_node_by_addr(registry, host, port) -> node_or_nil
```
Get node by address.

### Node Lifecycle

```sage
proc connect(registry, node) -> node
```
Transition to CONNECTING state.

```sage
proc connected(registry, node) -> node
```
Transition to CONNECTED state.

```sage
proc ready(registry, node) -> node
```
Transition to READY state.

```sage
proc disconnect(registry, node) -> node
```
Transition to DISCONNECTED state, close mailbox.

```sage
proc error(registry, node, err_msg) -> node
```
Transition to ERROR state with error message.

### Node Capabilities

```sage
proc add_capability(node, cap)
```
Add capability to node.

```sage
proc remove_capability(node, cap) -> bool
```
Remove capability from node.

```sage
proc has_capability(node, cap) -> bool
```
Check if node has capability.

### Node Discovery

```sage
proc list_nodes(registry) -> [node_id, ...]
```
List all node IDs.

```sage
proc list_connected(registry) -> [node, ...]
```
List connected nodes.

```sage
proc list_ready(registry) -> [node, ...]
```
List ready nodes.

```sage
proc count_nodes(registry) -> int
proc count_connected(registry) -> int
proc count_ready(registry) -> int
```

### Local Node

```sage
proc create_local_node(name, host, port) -> [registry, node]
```
Create and register local node.

```sage
proc set_local_node(registry, node)
```
Set local node reference.

```sage
proc get_local_node(registry) -> node
```
Get local node.

## Usage Example

```sage
import smp.node

# Create registry and local node
let result = create_local_node("worker-1", "192.168.1.100", 42000)
let registry = result[0]
let node = result[1]

# Add capabilities
add_capability(node, "compute")
add_capability(node, "storage")

# Transition states
connected(registry, node)
ready(registry, node)

# Register remote node
let remote = create_node(2, "coordinator", "192.168.1.1", 42000)
register(registry, remote)

# Get by name
let found = get_node_by_name(registry, "coordinator")
print("Found node: " + str(found["id"]))
```