# Security

## Model

injecy is designed so that **security never depends on the client being secret**.
Everything in this repository ships inside every distributed IPA and is therefore
considered public. The real security boundaries live on the server (rate limiting,
input validation, isolation) and on your device (certificates stay local, in the
Keychain / app sandbox).

- **No secrets in the repo.** The backend client secret (`Secrets.swift`) and the
  on-device TLS server pack (`deps/`) are git-ignored. Copy the provided
  `*.example` / `deps/README.md` templates to build.
- **Certificates stay on device.** Your `.p12` / `.mobileprovision` and their password
  are used locally for signing and are not uploaded by the client.
- **Backend is separate.** The reference API (`api.leadproject.lol`) is a closed
  service; its source, database and environment are not part of this project.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Instead, use GitHub's [private vulnerability reporting](../../security/advisories/new)
(Security → Advisories → *Report a vulnerability*). Include steps to reproduce and, if
possible, a proof of concept. We'll acknowledge as soon as we can and keep you updated
on the fix.

## Supported versions

Only the latest release is supported. Please update before reporting.
