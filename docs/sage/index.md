# SageSMP Documentation

Modular documentation for each SageSMP component.

## Modules

| Module | Description |
|--------|-------------|
| [Core](core.md) | Protocol opcodes, node states, defaults, pure-Sage JSON codec [`smp_json.sage`] |
| [Mailbox](mailbox.md) | FIFO message queues, handlers, ack tracking |
| [Crypto](crypto.md) | Signing, XOR cipher, token management |
| [Crypto/OTP](crypto/otp_crypto.md) | Pure Sage OTP encryption |
| [Crypto/SecureMsg](crypto/secure_msg.md) | Config-driven secure API |
| [Node](node.md) | Node registry, capabilities, discovery |
| [Transport](transport.md) | TCP socket, framing, heartbeat |
| [Client](client.md) | Client class, connection, messaging |
| [Server](server.md) | Server class, relay, routing |
| [RTOS](rtos.md) | Task scheduler, GC-aware cleanup |
| [Pi-hole](pihole.md) | Ad-blocking, DNS logging, packet capture |
| [Demo](demo.md) | Executable demonstrations |
| [Dashboard](dashboard.md) | FastAPI real-time console, SSE telemetry, PTY interactive terminal |

## Quick Start

```bash
./sagemake --init-config
./sagemake --all
./bin/demo_smp
```

## Building

```bash
./sagemake --sagesmp # Build unified single binary launcher
./sagemake --relay  # Build relay server
./sagemake --client # Build client shell  
./sagemake --demo   # Build demo
./sagemake --secure # Build secure message demo
```