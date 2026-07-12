# SageSMP Performance Benchmarks
# ==============================

gc_disable()

import sys
import smp
import smp.mailbox as smp_mailbox
import smp.smp_protocol as smp_protocol
import smp.crypto as smp_crypto
import smp.transport as smp_transport

# Helper to run a benchmark and print results
proc run_benchmark(name, num_iterations, fn):
    print "Running benchmark: " + name + " (" + str(num_iterations) + " iterations)..."
    let start = clock()
    fn(num_iterations)
    let elapsed = clock() - start
    if elapsed == 0:
        elapsed = 0.000001
    end
    let ops_per_sec = tonumber(num_iterations) / elapsed
    print "  Elapsed: " + str(elapsed) + " seconds"
    print "  Throughput: " + str(ops_per_sec) + " ops/sec"
    print ""
    return ops_per_sec
end

# 1. Benchmark Mailbox Throughput
proc bench_mailbox(n):
    let mbox = smp_mailbox.create_mailbox(1, n + 10)
    let msg = smp_mailbox.create_message(1, 2, 0, "Hello World Benchmark")
    for i in range(n):
        smp_mailbox.send(mbox, msg)
    end
    for i in range(n):
        smp_mailbox.recv(mbox)
    end
end

# 2. Benchmark Protocol Encoding
proc bench_protocol_encode(n):
    let msg = smp_protocol.build_data(1, 2, {"cmd": "test", "value": 12345, "payload": "Some benchmark payload content"})
    for i in range(n):
        let encoded = smp_protocol.encode(msg)
    end
end

# 3. Benchmark Protocol Decoding
proc bench_protocol_decode(n):
    let msg = smp_protocol.build_data(1, 2, {"cmd": "test", "value": 12345, "payload": "Some benchmark payload content"})
    let encoded = smp_protocol.encode(msg)
    for i in range(n):
        let decoded = smp_protocol.decode(encoded)
    end
end

# 4. Benchmark Cryptography (XOR + Base64)
proc bench_crypto(n):
    let data = "This is a moderately sized message payload used for testing cryptographic throughput of the XOR cipher."
    let key = "my-secret-key-for-benchmarking"
    for i in range(n):
        let encrypted = smp_crypto.xor_encrypt(data, key)
        let decrypted = smp_crypto.xor_decrypt(encrypted, key)
    end
end

# 5. Benchmark Buffer operations
proc bench_buffer(n):
    let buf = smp_transport.create_buffer(n * 20 + 100)
    for i in range(n):
        smp_transport.write_buffer(buf, "chunk")
    end
end

proc run_all():
    print "=== SageSMP Micro-Benchmarks ===\n"
    let m_ops = run_benchmark("Mailbox (Send + Recv)", 10000, bench_mailbox)
    let enc_ops = run_benchmark("Protocol Encode", 10000, bench_protocol_encode)
    let dec_ops = run_benchmark("Protocol Decode", 10000, bench_protocol_decode)
    let cry_ops = run_benchmark("Cryptography (Encrypt + Decrypt)", 5000, bench_crypto)
    let buf_ops = run_benchmark("Transport Buffer Writes", 20000, bench_buffer)
    
    print "=== Benchmark Summary (Ops/sec) ==="
    print "Mailbox (Send + Recv)           : " + str(m_ops)
    print "Protocol Encode                 : " + str(enc_ops)
    print "Protocol Decode                 : " + str(dec_ops)
    print "Crypto (Encrypt + Decrypt)      : " + str(cry_ops)
    print "Transport Buffer Writes         : " + str(buf_ops)
end

run_all()
