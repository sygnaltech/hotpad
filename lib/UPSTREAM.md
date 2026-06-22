# Vendored dependency: VD.ahk

`VD.ah2` in this folder is a **vendored copy** of the VD.ahk virtual-desktop
library. It is not authored here — it is bundled so the project works on a fresh
clone or ZIP download without any external setup.

| | |
|---|---|
| **Project** | VD.ahk |
| **Author** | Fu Pei Jiang ([@FuPeiJiang](https://github.com/FuPeiJiang)) |
| **Source** | https://github.com/FuPeiJiang/VD.ahk |
| **License** | MIT — see [VD.ahk-LICENSE](VD.ahk-LICENSE) |
| **Branch** | `v2_port` |
| **Pinned commit** | `67a88ba7418fe3bfb01ae0f7397cfd284782b88c` (2025-03-19) |

Only `VD.ah2` is vendored — it is self-contained (no further `#Include`s).
The examples/notes from the upstream repo are intentionally not bundled.

## Updating to a newer upstream version

Run [`update-vendor.ps1`](../update-vendor.ps1) from the repo root, or manually:

1. Grab the latest `VD.ah2` from the `v2_port` branch upstream.
2. Replace `lib/VD.ah2` with it.
3. Update the **Pinned commit** row above.
4. Smoke-test the suite (run `startup.ahk`, exercise the hotkeys).

Do not edit `lib/VD.ah2` directly — local edits would be lost on the next update.
