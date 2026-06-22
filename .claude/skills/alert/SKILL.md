---
name: alert
description: Play an audible alert AND report which VS Code instance / virtual desktop the current Claude Code session is running on. Use when you need the user's attention and want the notification to identify *where* the alert came from (which workspace, which desktop, and whether it's the desktop they're currently looking at). Proof-of-concept for desktop-aware notifications in the hotpad project.
---

# alert

Plays a recognizable tone (same channel as the `notify` skill) and then resolves the
running session's **VS Code window → virtual desktop**, reporting it to the terminal.

Unlike external sound-attribution, this works because the script runs *inside* the
instance it's reporting on — it already has the context, so no audio analysis is needed.

## How it works

1. **Tone** — `[console]::beep` tones (`problem` / `attention` / `success` / `tick`).
2. **Find my window** — matches the workspace folder leaf against open VS Code window
   titles (`… - <folder> - Visual Studio Code`).
3. **Find my desktop** — `IVirtualDesktopManager::GetWindowDesktopId` (public, stable COM
   API) for that window's HWND, plus `IsWindowOnCurrentVirtualDesktop`.
4. **Name the desktop** — maps the desktop GUID → name + ordinal via the registry
   (`…\Explorer\VirtualDesktops`), avoiding the version-fragile internal COM interface.

## How to invoke

Run from this skill's base directory via the PowerShell tool:

```powershell
& "<skill-base-dir>\alert.ps1" -Type problem
```

- `-Type` — `problem` (default) | `attention` | `success` | `tick`.
- `-Workspace` — folder to match; defaults to the current working directory.
- `-Alerter` — who raised it; defaults to `Claude`.
- `-Message` — optional line echoed alongside the sound.

The script blocks until the tone finishes, then prints the workspace, VS Code window,
desktop name/index, GUID, and whether that desktop is the one currently in view.

## Recording (for the hotpad UI)

When a desktop GUID is resolved, the script appends one tab-delimited line to
`%APPDATA%\Sygnal HotPad\alerts.log`:

```
epoch <TAB> {GUID} <TAB> project <TAB> alerter
```

The hotpad keypad (`virtual-combined.ahk`) reads this to show a yellow dot on any
desktop key with an unresolved alert, list recent alerts beside the keypad, and jump
to a desktop on click. An alert is **unresolved** until you visit its desktop. The
`{GUID}` is the stable desktop id (matches hotpad's own GUID formatting), so records
survive desktop reordering.
