---
name: alert
description: Reference implementation of a desktop-aware notification for Claude Code. Plays an audible alert AND records which VS Code instance / virtual desktop the session is running on, so the hotpad tray app can surface unaddressed alerts per desktop. This is an EXAMPLE for people wiring desktop-aware notifications into their own Claude install; the production path is the system-wide `notify` skill.
---

# alert (reference implementation)

A self-contained example of a **desktop-aware notification**: it plays a tone and
records the alert against the virtual desktop the current Claude/VS Code session is
running on. The hotpad tray app reads those records to show a yellow dot + clickable
list of unaddressed alerts per desktop.

> **This is a reference.** In day-to-day use the same recording is built into the
> system-wide **`notify`** skill (the sygnal plugin). Keep this one as a worked example
> for anyone who wants the behavior in their own Claude install *without* that plugin,
> or who wants to port the writer to another language.

## How it works

1. **Tone** — `[console]::beep` tones (`problem` / `attention` / `success` / `tick`).
2. **Find my window** — matches the workspace folder leaf against open VS Code window
   titles (`… - <folder> - Visual Studio Code`). The folder comes from the session's
   working directory, so nothing is hardcoded.
3. **Find my desktop** — `IVirtualDesktopManager::GetWindowDesktopId` (public, stable
   COM API) for that window's HWND.
4. **Record** — append one line to the shared alerts log (see the contract below).

## Setup in your own Claude install

1. **Pick a skill location.** Claude Code discovers skills in either:
   - a project: `<repo>/.claude/skills/<name>/`, or
   - your user scope: `~/.claude/skills/<name>/` (Windows: `C:\Users\<you>\.claude\skills\<name>\`).
2. **Copy this folder** (`SKILL.md` + `alert.ps1`) into that location.
3. **Invoke it** from the skill's base directory via the PowerShell tool:

   ```powershell
   & "<skill-base-dir>\alert.ps1" -Type problem
   ```

   - `-Type` — `problem` (default) | `attention` | `success` | `tick`.
   - `-Workspace` — folder to attribute the alert to; defaults to the working directory.
   - `-Alerter` — who raised it; defaults to `Claude`.
   - `-Message` — optional line echoed alongside the sound.
4. **Install/enable hotpad** (the reader). In hotpad's tray → **Settings**, tick
   **“Show desktop alerts”** (off by default). Then hold `Ctrl+Win` to see dots + the
   list; click a row to jump to that desktop.

## The alerts.log contract (implement your own writer in any language)

Writers append one **tab-delimited** line per alert to:

```
%APPDATA%\Sygnal HotPad\alerts.log
```

```
epoch <TAB> {GUID} <TAB> project <TAB> alerter
```

- **epoch** — Unix seconds (UTC) when the alert fired.
- **{GUID}** — the virtual desktop's stable id, formatted exactly as
  `{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}` (uppercase, braces). This is what
  `Guid.ToString("B").ToUpper()` produces, and it must match how hotpad formats a
  desktop GUID — otherwise the record won't line up with a keypad key. Get it from
  `IVirtualDesktopManager::GetWindowDesktopId(hwnd)` for your window.
- **project** — display name (here, the workspace folder leaf). Strip tabs/newlines.
- **alerter** — who raised it (here, `Claude`). Strip tabs/newlines.

hotpad treats an alert as **unresolved** until the user visits that desktop, then it's
resolved. The file is append-only; bound its growth if you write often (hotpad only
shows the latest 20).

## Notes

- The COM call is wrapped in C# via `Add-Type`, which needs **no SDK** — Windows
  PowerShell 5.1 + the in-box .NET Framework compile it on every supported Win10/11.
- Identification (`IVirtualDesktopManager` + registry for names) uses only **public**
  APIs. A "jump to another desktop" action would need the *internal* interface; hotpad
  handles jumping itself, so writers don't need it.
