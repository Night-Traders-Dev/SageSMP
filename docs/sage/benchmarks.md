# Performance Benchmarks

SageSMP includes a micro-benchmark suite to measure the performance characteristics of core operations (mailboxes, JSON serialization, encryption/decryption, and socket buffer operations).

## Benchmark Suite Structure

The benchmarks are located in `src/sage/demo/benchmark.sage` and cover:

1. **Mailbox throughput**: Measures 10,000 paired message `send` and `recv` operations.
2. **Protocol Serialization (Encode)**: Measures 10,000 JSON encoding cycles for typical SMP data packets.
3. **Protocol Deserialization (Decode)**: Measures 10,000 JSON parsing and conversion cycles from raw strings back to Sage dictionaries.
4. **Cryptography**: Measures 5,000 full message `xor_encrypt` + `xor_decrypt` roundtrips (using a 100-character test message with Base64 encoding).
5. **Transport Buffer Operations**: Measures 20,000 write cycles on the byte transport buffers.

---

## Running the Benchmarks

To run the benchmark suite, execute the following command:

```bash
sage -I src src/sage/demo/benchmark.sage
```

---

## Baseline Performance Results

Below are the baseline metrics compiled and run on the current environment:

| Module / Operation | Throughput (ops/sec) | Description |
|--------------------|----------------------|-------------|
| **Mailbox (Send + Recv)** | ~645 ops/sec | Enqueueing and dequeueing FIFO messages |
| **Protocol Encode** | ~5,928 ops/sec | JSON serialization of protocol envelopes |
| **Protocol Decode** | ~3,723 ops/sec | JSON parsing and dictionary validation |
| **Crypto (Encrypt + Decrypt)** | ~2,417 ops/sec | Base64-safe XOR encryption roundtrips |
| **Transport Buffer Writes** | ~6,331 ops/sec | Micro-writes to connection framing buffers |
