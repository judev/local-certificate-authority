# Certificate Authority for local development

```
./create-certificates.sh
```

This script will:

  - Create a CA certificate.
  - Optionally install it to your operating system's trust store (Linux) or
    keychain (macOS).
  - Create TLS certificates signed by this new Certificate Authority.

The generated certificates are stored in the `./certificates/` directory.

Please understand the security implications of using this, keep your certs safe and use a strong password.
