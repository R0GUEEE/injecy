<div align="center">

# injecy

**Sign apps and inject tweaks right on your iPhone — no jailbreak, no computer.**

[Website](https://leadproject.lol/injecy) · [Report a bug](../../issues)

</div>

---

injecy is an on-device iOS app for **signing IPAs and injecting tweaks** (`.dylib` /
`.deb`) straight on the device. It can sign with your own certificate, browse a tweak
library, import your own tweaks, and update itself over the air.

It is a fork of [**Feather**](https://github.com/khcrysalis/Feather) and is licensed
under the **GNU GPL v3** — see [`LICENSE`](LICENSE).

> **This repository is the iOS client only.** The backend it talks to
> (`api.leadproject.lol`) is a separate, closed-source service. To run injecy against
> your own server, point `InjecyBackend.base` at it and set your client secret in
> `Secrets.swift` (below).

## Features

- **Sign & install** IPAs on-device (Server or IDevice install).
- **Tweak library** — browse tweaks or import your own `.dylib` / `.deb`.
- **Self-updating** — updates itself, signed with your certificate, no re-sideloading.
- **Private** — certificates stay on the device. No account, no tracking.

## Building

Requirements: **Xcode 26+**, [**xcodegen**](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), and [`jq`](https://stedolan.github.io/jq/).

```sh
# 1. Clone
git clone https://github.com/<you>/injecy.git
cd injecy

# 2. Provide build-time secrets
cp injecy/Backend/Observable/Secrets.swift.example injecy/Backend/Observable/Secrets.swift
#    …then edit Secrets.swift and set your backend client secret.

# 3. Provide the on-device HTTPS server pack — see deps/README.md
#    (drop cert.json in deps/, or let the app fetch it at runtime)

# 4. Generate the Xcode project and open it
xcodegen generate
open injecy.xcodeproj
```

Notes:

- `injecy.xcodeproj` is generated from [`project.yml`](project.yml) and is **not**
  committed — always run `xcodegen generate` after cloning or editing `project.yml`.
- Version pins matter: `SWCompression` is pinned to `4.8.6` and `BitByteData` to
  `2.0.4` — newer releases raise the minimum iOS version and break the iOS 16 target.
- `AltSign` (in `Packages/`) is vendored and must be **embedded + code-signed** (already
  configured in `project.yml`); it crashes at launch otherwise.
- The Live Activity widget is disabled in the default build — an app extension needs its
  own provisioning that most (non-wildcard) certificates can't supply. See the comment
  in `project.yml` to re-enable it.

## Credits

Built on [Feather](https://github.com/khcrysalis/Feather) by khcrysalis and
contributors. Uses [Zsign](https://github.com/zhlynn/zsign),
[AltSign](https://github.com/SideStore/AltSign), and the SideStore/AltStore
`*.backloop.dev` server pack. Thank you to everyone in the sideloading community.

## License

[GNU General Public License v3.0](LICENSE). Because injecy is derived from Feather
(GPLv3), it stays GPLv3 — no additional restrictions may be added.
