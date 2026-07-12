# Test Suites Manual

SageSMP includes two automated test suites to verify protocol behavior, socket transport logic, and handle edge cases safely.

## Test Suite Structure

The tests are located in `src/sage/demo/`:
- **`example.sage`**: Standard integration tests demonstrating the primary components of SageSMP (Mailbox, Registry, Protocol Encoding, Transport, Crypto, and Node Integration).
- **`test_edge_cases.sage`**: A robust suite checking fault tolerance, invalid JSON inputs, cryptography mismatches, buffer bounds, and mailbox overflow handling.

---

## 1. Standard Integration Tests (`example.sage`)

This suite runs through the happy-path behavior of all SageSMP components:

- **Mailbox Tests**: Verifies FIFO queue operations, capacity enforcement, and tracking of message counts.
- **Node Registry**: Registers virtual nodes, retrieves them by name/ID, and checks discovery metadata.
- **Protocol Encoding**: Verifies message builder functions (`build_data`, `build_join`) and encodes them into JSON structures.
- **Transport**: Simulates TCP message framing and length prefixing.
- **Crypto**: Tests encryption/decryption of messages and digital node signatures.
- **Full Integration**: Tests local mailbox loopbacks.

---

## 2. Edge Case & Fault Tolerance Tests (`test_edge_cases.sage`)

This suite ensures the protocol behaves reliably when encountering failures, overflows, or malicious payloads:

- **JSON / Protocol Validation**:
  - Validates that invalid JSON inputs (corrupted syntax) resolve to `nil` rather than causing runtime crashes.
  - Verifies that empty strings or payloads missing required keys (`op`, `sender`, `target`) fail validation.
- **Transport & Buffering Bounds**:
  - Enforces write limits on the connection buffers, confirming that attempts to exceed capacity return `false`.
  - Verifies that truncated frames (mismatched length prefixes) are detected and handled without data corruption.
- **Cryptography Robustness**:
  - Asserts that decryption attempts with wrong keys do not match original plaintext.
  - Confirms that modified signatures or incorrect node IDs fail authenticity checks.
- **Node Registry Safety**:
  - Asserts that duplicate registrations for the same node ID do not corrupt the registry or inflate node counts.
  - Verifies that retrieving non-existent nodes returns `nil` safely.
- **Mailbox Overflow Handling**:
  - Asserts that blocking `send` calls raise a `"mailbox full"` exception when capacity is exceeded.
  - Asserts that non-blocking `try_send` calls return `false` gracefully when capacity is exceeded.
  - Verifies empty mailbox reads return `nil` cleanly.

---

## Running the Test Suite

Use the build script `sagemake`:

```bash
# Runs both integration and edge case test suites
./sagemake --test
```

Alternatively, you can run them directly using the Sage interpreter (make sure to specify the search path using `-I src`):

```bash
# Run integration tests
sage -I src src/sage/demo/example.sage

# Run edge case tests
sage -I src src/sage/demo/test_edge_cases.sage
```
