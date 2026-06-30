# Crypto Module

Cryptographic utilities for SMP message authentication and encryption.

## Overview

The crypto module provides message signing, verification, and obfuscation utilities. It includes:
- XOR cipher for payload obfuscation
- Checksum for message integrity
- Node ID signing for authentication
- Challenge-response authentication
- Token generation and validation
- Secure envelope creation

## API Reference

### XOR Cipher

```sage
proc xor_encrypt(data, key) -> encrypted_string
```
XOR-based encryption of data with key.

```sage
proc xor_decrypt(data, key) -> decrypted_string
```
XOR-based decryption (same as encrypt, symmetric).

### Checksum

```sage
proc checksum(data) -> int
```
Compute 16-bit checksum of data.

```sage
proc verify_checksum(data, expected) -> bool
```
Verify data against expected checksum.

### Node Authentication

```sage
proc generate_node_secret() -> string
```
Generate a secret for node authentication using timestamp and hash.

```sage
proc sign_node_id(node_id, secret) -> signature
```
Sign a node ID with secret.

```sage
proc verify_node_signature(node_id, signature, secret) -> bool
```
Verify node signature.

### Message Authentication

```sage
proc sign_message(msg, secret) -> signed_message
```
Sign and checksum a message. Returns dict with message, checksum, and signature.

```sage
proc verify_message(signed_msg, secret) -> bool
```
Verify signed message integrity and signature.

### Challenge-Response

```sage
proc create_challenge() -> challenge_string
```
Create a random challenge using timestamp and hash.

```sage
proc create_response(challenge, secret) -> response
```
Create response to challenge.

```sage
proc verify_response(challenge, response, secret) -> bool
```
Verify challenge response.

### Token Management

```sage
proc generate_token(node_id, secret, ttl_secs) -> token_dict
```
Generate authentication token with TTL.

```sage
proc validate_token(token, secret) -> bool
```
Validate token (checks expiration and signature).

### Secure Envelope

```sage
proc create_secure_envelope(sender_id, recipient_id, payload, secret) -> envelope
```
Create encrypted envelope with checksum.

```sage
proc open_secure_envelope(envelope, secret) -> payload
```
Decrypt and verify envelope. Raises error on checksum failure.

## Usage Example

```sage
import smp.crypto

# Generate secret
let secret = generate_node_secret()

# Sign message
let signed = sign_message({"data": "hello"}, secret)

# Verify
if verify_message(signed, secret):
    print("Message verified")

# Secure envelope
let env = create_secure_envelope(1, 2, "Secret!", secret)
let payload = open_secure_envelope(env, secret)
print(payload)  # "Secret!"
```