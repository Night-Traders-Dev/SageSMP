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

```bash
# AST Interpreter (default)
sage -I src src/sage/demo/benchmark.sage

# JIT (profiling-guided native compilation)
sage -I src --jit src/sage/demo/benchmark.sage
```

---

## Performance Results (SageLang v4.0.8)

### AST Interpreter vs JIT Comparison

| Module / Operation | AST Interpreter (ops/sec) | JIT (ops/sec) | Δ |
|--------------------|--------------------------|---------------|---|
| **Mailbox (Send + Recv)** | 743 | 731 | -1.6% |
| **Protocol Encode** | 33,753 | 34,532 | +2.3% |
| **Protocol Decode** | 6,045 | 6,225 | +3.0% |
| **Crypto (Encrypt + Decrypt)** | 2,531 | 2,583 | +2.1% |
| **Transport Buffer Writes** | 6,354 | 6,333 | -0.3% |

### Notes

- GC is disabled during benchmarks (`gc_disable()`) to isolate pure computational throughput.
- The JIT backend generates native tail-call trampolines for hot functions (≥100 calls), bypassing the AST tree-walker for profiled code paths.
- JIT now supports x86-64, AArch64, and RV64 architectures (v4.0.8+).
- Mailbox throughput is I/O-bound (array resizing), so JIT/AST performance is nearly identical for that workload.
- Protocol encode/decode and crypto show consistent 2-3% improvements under JIT due to reduced dispatch overhead in hot inner loops.
