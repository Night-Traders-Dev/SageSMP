# Secure Message API

End-to-end encryption API for relay and client modules.

## Overview

The secure message module provides configuration-driven OTP encryption for use by relay and client modules. It wraps the core OTP/crypto functionality with user-configurable defaults.

## Configuration

Users can customize these values at the top of the file or via `.smp_config`:

```sage
let SMP_CONFIG = {
    "relay_host": "0.0.0.0",
    "relay_port": 42000,
    "max_connections": 64,
    "enable_logging": true,
    "log_file": "/tmp/smp_relay.log",
    "default_secret_key": "change_this_key",
    "default_otp_passphrase": "change_this_passphrase",
    "default_otp_seed": 12345
}

let CLIENT_CONFIG = {
    "server_host": "127.0.0.1",
    "server_port": 42000,
    "reconnect_attempts": 3,
    "default_secret_key": "change_this_key",
    "default_otp_passphrase": "change_this_passphrase",
    "default_otp_seed": 12345
}
```

## Using Configuration File

```bash
./sagemake --init-config
# Edit .smp_config with your settings
./sagemake --all
```

## API Reference

### Core Functions (Internal)

```sage
proc simple_hash(value, seed) -> int
```
Pure Sage hash function for key derivation.

```sage
proc generate_otp_key(passphrase, length, seed) -> [int, ...]
```
Generate OTP key bytes from passphrase.

### Signing

```sage
proc sign_message(message, secret_key, node_id) -> [int, int]
```
Create hash-based signature.

```sage
proc verify_signature(message, signature, secret_key, node_id) -> bool
```
Verify signature.

### OTP Encryption

```sage
proc otp_encrypt(message, otp_key) -> encrypted_string
proc otp_decrypt(encrypted, otp_key) -> decrypted_string
```

### Secure Message API

```sage
proc secure_send(message, secret_key, otp_pass, otp_seed, sender_id, recipient_id) -> envelope
```
Create and encrypt message. Returns envelope with:
- `payload` - Encrypted message
- `otp` - OTP key
- `sig` - Signature
- `from` - Sender ID
- `to` - Recipient ID

```sage
proc secure_receive(envelope, secret_key, otp_pass, otp_seed, expected_sender) -> payload_or_nil
```
Verify signature and decrypt. Returns nil if invalid.

```sage
proc secure_send_with_config(message, config, sender_id, recipient_id) -> envelope
proc secure_receive_with_config(envelope, config, expected_sender) -> payload_or_nil
```
Config-driven versions using SMP_CONFIG or CLIENT_CONFIG.

## Usage in Relay

```sage
# In relay.sage
let rule = add_relay_rule("hello", "192.168.1.100", 42001, "Hello!", "key", "pass", 100)

# Forward securely
let forwarded = secure_forward(msg, rule)
```

## Usage in Client

```sage
# In client_shell.sage
client_send_secure(host, port, message, secret_key, otp_pass, otp_seed, sender_id, recipient_id)
```

## Security Model

1. **Encryption**: OTP encryption with key derived from passphrase + seed
2. **Signing**: Dual-hash signature with secret key + node ID
3. **Verification**: Signature check before decryption
4. **Configuration**: Keys stored in config file, shared between sender/receiver