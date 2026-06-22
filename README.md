**Library & Setup Instructions all updated to AHK 2.0** 

# Sygnal HotPad

A hotkey + numpad virtual-desktop manager for Windows 11 — one tray app to switch desktops, move and pin windows, name desktops, and pop a numpad-style preview HUD (hold `Ctrl+Win`).

This started as a set of fixes for Win11 window management, specifically moving the active window to the next desktop and cascading/tiling windows.

The App Specific Switcher came about because I wanted to duplicate the MacOS functionality of Using command-backtick (⌘-\`) to toggle between windows.  That comes as close as I could get it, which works pretty well I think.

I started with wanting to move the active window to the next desktop.  This [stackoverflow had a few really good answers](https://superuser.com/questions/1685845/moving-current-window-to-another-desktop-in-windows-11-using-shortcut-keys) that built on each other.  Last user was nice enough to give [an AHK how-to](https://superuser.com/a/1728476):

After I did this, making a CascadeWindows or TileWindows script seemed like it might not be too hard after [finding this ancient post](https://www.autohotkey.com/board/topic/80580-how-to-programmatically-tile-cascade-windows/).
It needed lots of tweaking to get it working, but it works well with multiple desktops without messing up the windows on other desktops.

While looking to see if there was anything else useful to implement, I came across a poorly implemented application switcher with no reverse.  I really missed this functionality from MacOS, Command+`, so I implemented it as best I could without events to know if the focus order had changed.

## Overview 

[AutoHotKey](https://www.autohotkey.com/) is free, and is now at Version 2. 

Once AutoHotKey is installed, scripts can be placed anywhere on your system, and end in `.ahk` or `.ah2` for v2 scripts.  
Double click to execute them, and they will remain running until terminated via the AHK dash or system restart. 

The scripts in this library utilize FuPeiJiang's Virtual Desktop library **VD.ahk**, which adds AutoHotkey functions for managing virtual desktops. **It is bundled with this repo** (vendored as [`lib/VD.ah2`](lib/VD.ah2)), so there is nothing extra to download — a clone or ZIP download of this repository works on its own. See [`lib/UPSTREAM.md`](lib/UPSTREAM.md) for the source, version, and how to update it.

The virtual-desktop features are bundled into a single script, **`virtual-combined.ahk`**, launched by **`startup.ahk`** — so everything runs as **one process / one tray icon** ("Sygnal HotPad"). You just run `startup.ahk`.

Two extra features live in their own standalone scripts under `extras/` (run them separately if you want them):

- `extras/virtual-cascade.ahk` — cascade / tile windows
- `extras/app-specific-tab-switcher.ahk` — macOS-style ⌘-` app-window cycling

*The full hotkey list, and how to auto-start with Windows, are below.*

### Repository layout

```
virtual-combined.ahk    the whole suite (one tray icon)
startup.ahk             entry point — run this; it loads virtual-combined
virtual-icon.*          tray icon
assets/                 keypad key icons
lib/                    bundled VD.ahk dependency (see lib/UPSTREAM.md)
reference/              the individual scripts that were folded into the suite
extras/                 standalone scripts not part of the suite (cascade, app switcher)
legacy/                 older / niche / personal scripts and notes, kept for reference
```

## Setup Process

1.  Download and install [AutoHotKey v2.0](https://www.autohotkey.com/).

2.  Get this repository, either way works:
    - **Git:** `git clone https://github.com/sygnaltech/Win11AutoHotKeyFixes.git`
    - **No git:** use GitHub's green **Code → Download ZIP** and extract it anywhere.

That's it — the VD.ahk library is already bundled in `lib/`, so there is no separate dependency to clone.

## Running the Script

Double-click **`startup.ahk`**. That loads the whole virtual-desktop suite into a single tray icon. All the hotkeys below (navigate, move, numpad, pin, preview keypad, rename) are then live.

Optionally, also double-click the standalone extras if you want them:

- `extras/virtual-cascade.ahk` — cascade / tile windows
- `extras/app-specific-tab-switcher.ahk` — app-window cycling

### Troubleshooting 

If you get any errors when you run the script, the most likely cause is;

- You have downloaded AHK v1 accidentally instead of v2 

(The VD.ahk library is bundled in `lib/`, so the old "two adjacent folders / wrong branch" problems no longer apply.)

### Automatically Installing these at Windows Startup 

1. Create a shortcut to **`startup.ahk`** (and to any standalone extras you use, e.g. `virtual-cascade.ahk`). 

2. Press `Win+R` and type `shell:startup` to see your Windows startup folder. 

3. Drag those shortcuts in. 




## Usage

These hotkeys come from the **suite** (`startup.ahk` → `virtual-combined.ahk`). The numpad hotkeys assume **NumLock is ON** (they use the digit keys `Numpad0`–`Numpad9`, where `Numpad0` = desktop 10).

### Navigating desktops

 - `Ctrl + Win + Left` / `Right`: Switch to the previous / next desktop (wraps around)
 - `Ctrl + Win + Numpad1…9`: Jump straight to desktop 1–9 (creates it if it doesn't exist)
 - `Ctrl + Win + Numpad0`: Jump to desktop 10

### Moving the active window

 - `Ctrl + Alt + Win + Left` / `Right`: Move window to the previous / next desktop **and follow it** (alias: `Ctrl + Win + Shift + Left/Right`)
 - `Ctrl + Alt + Win + Numpad0…9`: Move window to that desktop (1–10) and follow it
 - `Alt + Win + Left` / `Right` (or `Numpad0…9`): Move window to that desktop but **stay** where you are

### Pinning apps / windows to every desktop

 - `Ctrl + Win + Z`: Toggle pinning the active application's executable (all of its windows show on every desktop)
 - `Ctrl + Win + X`: Toggle pinning only the currently focused window

### Desktop preview, naming & settings

 - **Hold `Ctrl + Win`**: Show a numeric-keypad preview of your desktops on the primary monitor — keys `1`–`9` are desktops 1–9 (1 = bottom-left, 9 = top-right) and `0` is desktop 10. The current desktop's key is highlighted, and each desktop's name shows beneath its number. Release to dismiss. (The `= / * BS − + Enter` keys are placeholders for now.)
 - `Ctrl + Win + NumpadDot`: Rename the current desktop. Names use the native Windows 11 desktop names, so they persist and also appear in Task View.
 - **Tray icon → Settings**: Choose the keypad size — Small (100%), Medium (150%), or Large (200%). Your choice is saved to `%APPDATA%\Sygnal HotPad\settings.ini` and remembered across restarts.

---

The following come from the **standalone extras** (run their script separately):

### Cascading / tiling windows — `extras/virtual-cascade.ahk`

 - `Win + Alt + C`:  Cascade all windows on the desktop
 - `Win + Alt + H`:  Tile all windows horizontally
 - `Win + Alt + V`:  Tile all windows vertically
 - Add `+ Shift` to any of the above: only cascade/tile windows of the same executable (e.g. all Chrome windows)

### App-specific switcher (macOS ⌘-`) — `extras/app-specific-tab-switcher.ahk`

 - ``Alt + ` ``:  Switch to the most recent non-focused window of the same app
 - ``Alt + Shift + ` ``:  Switch to the oldest non-focused window of the same app

## Other 

If someone has a better suggestion for the cascading windows shortcuts, feel free to suggest it and any other ideas you might have.

## Credits & Third-Party

This project bundles, unmodified, the **VD.ahk** virtual-desktop library:

- **VD.ahk** by Fu Pei Jiang ([@FuPeiJiang](https://github.com/FuPeiJiang)) — https://github.com/FuPeiJiang/VD.ahk — MIT License.
  Vendored as [`lib/VD.ah2`](lib/VD.ah2); see [`lib/UPSTREAM.md`](lib/UPSTREAM.md) for the pinned version and [`lib/VD.ahk-LICENSE`](lib/VD.ahk-LICENSE) for its license.

This repository is MIT licensed (see [LICENSE](LICENSE)). The bundled VD.ahk library remains under its own MIT license held by its author.

## License

[MIT](LICENSE)

