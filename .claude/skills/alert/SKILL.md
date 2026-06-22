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
- `-Message` — optional line echoed alongside the sound.

The script blocks until the tone finishes, then prints the workspace, VS Code window,
desktop name/index, GUID, and whether that desktop is the one currently in view.

## Status

Proof-of-concept (identification only). Possible next steps once verified:
`FlashWindowEx` the window's taskbar button from another desktop, and an optional
"jump to that desktop" action (which *would* need the internal API / VirtualDesktopAccessor).
