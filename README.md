**Library & Setup Instructions all updated to AHK 2.0** 

# Win11AutoHotKeyFixes
This is to resolve deficiencies of Win11 window management, specifically moving active window to next desktop and cascading/tiling windows.

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

To enable the hotkeys you want, you'll enter the `Win11AutoHotKeyFixes` folder and run the AHK scripts you want;

- `VD-move-window-with-desktop.ahk`
- `VD-cascade.ahk`
- `AppSpecificTabSwitcher.ahk`
- `VD-pin-app.ahk`

These can be simply double-clicked to execute.

*Details on what hotkeys each of these enable, and how to automatically start them with Windows, are below.*

## Setup Process

1.  Download and install [AutoHotKey v2.0](https://www.autohotkey.com/).

2.  Get this repository, either way works:
    - **Git:** `git clone https://github.com/sygnaltech/Win11AutoHotKeyFixes.git`
    - **No git:** use GitHub's green **Code → Download ZIP** and extract it anywhere.

That's it — the VD.ahk library is already bundled in `lib/`, so there is no separate dependency to clone.

## Running the Script

Navigate to the `Win11AutoHotKeyFixes` and double-click the scripts you want to execute. 

- `VD-move-window-with-desktop.ahk`
- `VD-cascade.ahk`
- `AppSpecificTabSwitcher.ahk`
- `VD-pin-app.ahk`

### Troubleshooting 

If you get any errors when you run the script, the most likely cause is;

- You have downloaded AHK v1 accidentally instead of v2 

(The VD.ahk library is bundled in `lib/`, so the old "two adjacent folders / wrong branch" problems no longer apply.)

### Automatically Installing these at Windows Startup 

1. For each script you want to autostart with Windows, create a shortcut. 

2. Press `Win+R` and type `shell:startup` to see your Windows startup folder. 

3. Drag those shortcuts in. 




## Usage

Functionality is divided into 4 scripts- 

### Moving windows

*Run the `VD-move-window-with-desktop.ahk` script.*

 - `Win + Ctrl + Shift + Left`:  Move active window to the left desktop and follow it
 - `Win + Ctrl + Shift + Right`: Move active window to the right and follow it

### Cascading windows

*Run the `VD-cascade.ahk` script.*

 - `Win + Alt + C`:  Cascade all windows on desktop
 - `Win + Alt + H`:  Tile all windows on desktop horizontally
 - `Win + Alt + V`:  Tile all windows on desktop vertically
 - Add `+ Shift` to any of the above: Will only Cascade/Tile matching executables (eg all chrome windows)

### App Specific Switcher (Command+`)

*Run the `AppSpecificTabSwitcher.ahk` script.*

 - ``Alt + ` ``:  Switch to most recent non-focused window of same app
 - ``Alt + Shift + ` ``:  Switch to oldest non-focused windows of same app

### Pinning apps/windows to every desktop

*Run the `VD-pin-app.ahk` script.*

 - `Ctrl + Win + Z`: Toggle pinning for the active application's executable (all of its windows show on every desktop)
 - `Ctrl + Win + X`: Toggle pinning for only the currently focused window

## Other 

If someone has a better suggestion for the cascading windows shortcuts, feel free to suggest it and any other ideas you might have.

## Credits & Third-Party

This project bundles, unmodified, the **VD.ahk** virtual-desktop library:

- **VD.ahk** by Fu Pei Jiang ([@FuPeiJiang](https://github.com/FuPeiJiang)) — https://github.com/FuPeiJiang/VD.ahk — MIT License.
  Vendored as [`lib/VD.ah2`](lib/VD.ah2); see [`lib/UPSTREAM.md`](lib/UPSTREAM.md) for the pinned version and [`lib/VD.ahk-LICENSE`](lib/VD.ahk-LICENSE) for its license.

This repository is MIT licensed (see [LICENSE](LICENSE)). The bundled VD.ahk library remains under its own MIT license held by its author.

## License

[MIT](LICENSE)

