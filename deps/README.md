# deps/ — on-device HTTPS server pack

injecy installs signed apps over the air from a local HTTPS server running on the
device. iOS refuses plain-HTTP `itms-services` installs, so the local server needs a
certificate that is valid for a name resolving to `127.0.0.1`. Like other apps in the
AltStore / SideStore / Feather family, injecy uses the community **`*.backloop.dev`**
wildcard certificate (backloop.dev and its subdomains resolve to localhost).

These files are **git-ignored** because they contain a private key — even a public,
shared one shouldn't sit in version control (secret scanners flag it, and you may want
to swap in your own).

Expected files (not committed):

| file             | what it is                                   |
| ---------------- | -------------------------------------------- |
| `cert.json`      | server pack (`cert`, `key1`, `key2`, `ca`…)  |
| `server.pem`     | private key (derived from `cert.json`)       |
| `server.crt`     | certificate                                  |
| `commonName.txt` | the cert's common name (e.g. `*.backloop.dev`) |

**How to get them:** grab a server pack from any SideStore/AltStore-compatible source,
or the app can fetch one at runtime (`FR.downloadSSLCertificates`). The `Makefile`
`prepare` step regenerates `server.pem` from `cert.json`:

```sh
jq -r '.key1, .key2' deps/cert.json > deps/server.pem
```
