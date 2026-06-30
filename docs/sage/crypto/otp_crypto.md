# OTP Crypto Module

Pure Sage One-Time Pad (OTP) encryption for end-to-end secure messaging.

## Overview

The OTP crypto module provides end-to-end encryption using a pure Sage implementation of OTP encryption. This module is designed for secure communication between nodes where messages must be encrypted before sending and decrypted after receiving using matching keys.

## Key Features

- **Pure Sage Implementation**: No external dependencies
- **OTP Encryption**: One-Time Pad style encryption with derived keys
- **Message Signing**: Hash-based signature verification
- **Configurable Keys**: Passphrase-based key derivation

## API Reference

### Key Generation

```sage
proc simple_hash(value, seed) -> int
```
Pure Sage hash function using DJB2 variant.

```sage
proc generate_otp_key(passphrase, length, seed) -> [int, ...]
```
Generate OTP key bytes from passphrase and seed. The key length determines how many bytes are generated.

### Signing

```sage
proc sign_message(message, secret_key, node_id) -> [int, int]
```
Sign a message with secret key and node ID. Returns dual-signature array.

```sage
proc verify_signature(message, signature, secret_key, node_id) -> bool
```
Verify message signature against expected values.

### OTP Encryption

```sage
proc otp_encrypt(message, otp_key) -> encrypted_string
```
Encrypt message using OTP key (byte-by-byte addition mod 256).

```sage
proc otp_decrypt(encrypted, otp_key) -> decrypted_string
```
Decrypt message using OTP key (byte-by-byte subtraction mod 256).

### Secure Message

```sage
proc create_secure_message(message, secret_key, otp_passphrase, otp_seed, sender_id, recipient_id) -> envelope
```
Create a secure message envelope with:
- `payload` - OTP-encrypted message
- `otp` - OTP key for decryption
- `sig` - Signature array
- `from` - Sender ID
- `to` - Recipient ID

```sage
proc read_secure_message(msg, secret_key, otp_passphrase, otp_seed, expected_sender) -> payload_or_nil
```
Verify signature and decrypt payload. Returns nil if signature invalid.

## Usage Example

```sage
import smp.crypto.otp_crypto

let secret = "my_secret_key_123"
let otp_pass = "otp_passphrase_456"
let message = "Hello secure world!"

# Create secure message
let envelope = create_secure_message(message, secret, otp_pass, 789, 1, 2)

# Send envelope["payload"] over network...

# Receive and decrypt
let decrypted = read_secure_message(envelope, secret, otp_pass, 789, 1)
print("Decrypted: " + decrypted)  # Original message
```

## Security Considerations

- The OTP key is derived deterministically from passphrase + seed
- Both sender and receiver must use the same secret_key, otp_passphrase, and otp_seed
- Signature verification prevents tampering
- For production use, consider using true random OTP keys exchanged via QR codes or secure channels