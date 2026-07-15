# SageSMP Deployment and Compilation

## Unified Binary

SageSMP operates as a unified binary containing all node roles:
- `relay`: OrangePi Central Relay Server
- `pi2`: Pi2 Client (with Pihole telemetry)
- `pi4`: Pi4 Client (with Prometheus/Grafana and cross-compilation)
- `shell`: Interactive Universal Client Shell

Instead of shipping multiple scripts, all logic has been combined into `src/sage/sagesmp.sage`.

## AOT Compilation

SageLang supports AOT (Ahead-of-Time) compilation. We've enhanced the AOT compiler to correctly emit C-code equivalents for all global scoped variables and built-in standard library functions, allowing seamless compilation.

### Cross-Compilation for Multiple Architectures

Because AOT compilation translates Sage code into C code, cross-compilation is trivial given the correct GCC cross-compilers (`aarch64-linux-gnu-gcc` and `riscv64-linux-gnu-gcc`).

```bash
# Generate C source
sage --aot src/sage/sagesmp.sage > sagesmp.c

# Compile for x86_64
gcc -std=c11 -O2 sagesmp.c -o sagesmp-x86_64 -lm

# Compile for aarch64 (Raspberry Pi 4)
aarch64-linux-gnu-gcc -std=c11 -O2 sagesmp.c -o sagesmp-aarch64 -lm

# Compile for rv64 (OrangePi)
riscv64-linux-gnu-gcc -std=c11 -O2 sagesmp.c -o sagesmp-rv64 -lm
```

### JIT-Guided AOT

You can also use Profile-Guided Optimization by feeding the JIT profiler data into the AOT compiler.
This analyzes variable types at runtime and hardcodes them in the C output for better performance:
```bash
sage --aot --jit src/sage/sagesmp.sage -o sagesmp_optimized
```

## SSH ProxyJump Setup

For seamless connection into the Pi2 and Pi4 nodes, set up a ProxyJump via the OrangePi relay in your `~/.ssh/config`:

```ssh-config
Host OrangePi
    HostName 192.168.254.44
    User kraken

Host pi2
    HostName 10.42.1.109
    User pi
    ProxyJump OrangePi

Host pi4
    HostName 10.42.0.141
    User ubuntu
    ProxyJump OrangePi
```
