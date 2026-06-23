# AGENTS.md

## Overview

This document provides a detailed technical analysis of all AutoHotKey scripts in the Win11AutoHotKeyFixes repository. These scripts are designed to enhance Windows 11 window management capabilities and replicate useful macOS features.

## Architecture

All scripts are written in AutoHotKey v2.0 and depend on the [VD.ahk](https://github.com/FuPeiJiang/VD.ahk) library (v2_port branch) for virtual desktop management functionality.

### Current layout (consolidated)

The virtual-desktop functionality is now consolidated into a **single** script, [virtual-combined.ahk](virtual-combined.ahk), which runs as one process / one tray icon (a blue connection-mark icon, `virtual-icon.ico`, with the tray tooltip "Sygnal HotPad").

- **[hotpad.ahk](hotpad.ahk)** is the entry point. It `#Include`s `virtual-combined.ahk` so the suite runs in-process, and retains a `LaunchScript` helper + (currently empty) `scripts` list for launching any *future* standalone scripts as separate processes.
- **[virtual-combined.ahk](virtual-combined.ahk)** merges what used to be five separate scripts: `virtual-navigate-wraparound.ahk`, `virtual-move-window.ahk`, `virtual-numpad-desktops.ahk`, `virtual-pin-app.ahk`, and `virtual-grid.ahk` (the preview HUD + desktop rename). It dedupes their shared setup, the library `#Include`, and helpers (`WaitForDesktop`, `AdjacentDesktop`, `MoveWindowToDesktop`).
- The original scripts are **kept in the repo and remain standalone-runnable**, but are **no longer launched** by `hotpad.ahk`. The older `virtual-move-window-with-desktop.ahk` was merged into `virtual-move-window.ahk` and removed.

Directory layout:

```
virtual-combined.ahk    the whole suite (one tray icon)
hotpad.ahk              entry point — loads virtual-combined
virtual-icon.*          tray icon
assets/keys/            keypad key icons (PNG + SVG source)
assets/screenshots/     doc images (keypad-hud.svg)
lib/                    bundled VD.ahk dependency (vendored; see lib/UPSTREAM.md)
reference/              the individual scripts folded into the suite (kept for reference)
extras/                 standalone scripts not part of the suite (cascade + _winarrange, app switcher)
legacy/                 older / niche / personal scripts and notes
```

Note: scripts in `reference/` and `extras/` reach the library via `../lib/VD.ah2` (one level up); the root suite uses `lib/VD.ah2`.

#### Preview keypad + Config dialog + launchers (in virtual-combined.ahk)

These features live only in the consolidated script (their original was `virtual-grid.ahk`):

- **Preview keypad** — holding `Ctrl+Win` shows a full numeric-keypad HUD rendered with **GDI+** onto a **layered window** (`UpdateLayeredWindow`, `WS_EX_LAYERED | WS_EX_NOACTIVATE`), centered on the **primary** monitor. Layout matches a real numpad: `= / * BS` / `7 8 9 −` / `4 5 6 +` / `1 2 3 Enter` / `0 .`, so `1`–`9` map to desktops 1–9 (1 = bottom-left, 9 = top-right) and the `0` key is **desktop 10** (labelled "0"). The current desktop's key is filled blue; each desktop's name is drawn beneath its number. The operator keys (`= / * − + Enter`) draw the **name of their assigned launcher** beneath the glyph (see Launchers), and the `.` key always shows **"Config"**. The backspace key uses a bundled icon (`assets/keys/bs.png`, rasterized from `bs.svg`). Driven by a lightweight `SetTimer CheckChord, 75` poll; a `class VirtualGrid` holds geometry, ARGB colors, the `Scale` setting, and runtime state. Renderer entry point is `RenderKeypad()` (+ `Kp*` helpers, incl. `KpKeyName()` for the captions); redraws only on change. Purely informational — actual switching uses the `Ctrl+Win+Numpad` hotkeys.
- **Config dialog** — `Ctrl+Win+NumpadDot` (or `NumpadDel` with NumLock off), or the tray **Settings** / **Launchers** entries, open one dark, keypad-styled tabbed dialog (`ShowHotpadDialog`) with custom on-theme tab headers (selected tab filled blue; only the background toggles via `Opt()`+`Redraw`). Tabs:
  - **Desktop** — rename the current desktop. Names use the **native Windows 11 desktop names** via `VD.setNameToDesktopNum` / `VD.getNameFromDesktopNum`, so they persist, survive reordering, and appear in Task View.
  - **Settings** — keypad size **Small (100%) / Medium (150%) / Large (200%)** (the whole keypad — keys, fonts, icon, radii — scales by `VirtualGrid.Scale`), and a **Show desktop alerts** checkbox (`VirtualGrid.AlertsEnabled`, off by default; see Desktop alerts below).
  - **Launchers** — a `Key | Name | Action | Target` ListView; double-click a row to open the `EditLauncher` sub-dialog (Action = Do nothing / Application / Open Chrome, plus a Name, and either a Browse-able program path + args or a profile dropdown).
  A single **Save** commits all at once — desktop name, scale (`SaveScale`), the alerts toggle (`SaveAlertsEnabled`), and launchers (`SaveLaunchers`) — and re-binds the operator hotkeys immediately.
- **Configurable launchers** — each keypad operator key (`Ctrl+Win` + `+ − * / = ( ) Enter`) can launch an **application** (path + optional args) or open **Chrome** with a chosen profile. `LauncherDefs()` maps id → glyph → the AHK hotkey strings to bind (numpad + main-row where both are cleanly nameable; main-row `*`/`+` are skipped — they collide with AHK's wildcard/Shift syntax — so the numpad versions cover them). State lives in `class LaunchCfg`; `ApplyLaunchers()` binds assigned keys On and the rest Off, and `RunLauncher()` dispatches. Each assignment carries a **name** shown on the HUD. The `/` key seeds to the Chrome profile menu so the prior Chrome-on-`/` still works.
- **Chrome launcher** — `LaunchChromeProfile()` runs `chrome.exe --profile-directory="<dir>" --new-window`, which opens a **new window on the current virtual desktop**. (Launching with no profile shows Chrome's own picker, which *activates an existing window* of the chosen profile — and Windows then follows it to whatever desktop it lives on — so we pin the profile ourselves and offer our own dark menu, `ChromeMenu()`, built from a live scan of `%LOCALAPPDATA%\Google\Chrome\User Data` via `ChromeProfileDirs()`.) `ChromePath()` resolves the exe via the App Paths registry key, then common install dirs.
- **Settings store (persisted)** — saved to `%APPDATA%\Sygnal HotPad\settings.ini`, kept out of the repo so it survives updates: `[Keypad] Scale=…`, `[Alerts] Enabled=0|1`, plus one `[Launch_<id>]` section per assigned key (`Action` = `app`|`chrome`, `Path`, `Args`, `Profile`, `Name`). Loaded at startup by `LoadConfig` / `LoadLaunchers`.

#### Desktop alerts (in virtual-combined.ahk)

Opt-in, off by default (`VirtualGrid.AlertsEnabled`, toggled on the Settings tab). Surfaces **unaddressed notifications per virtual desktop**: a yellow dot on a desktop's keypad key, plus a clickable list beside the keypad.

- **Data contract (writer → reader).** External tools *append* one tab-delimited line per alert to `%APPDATA%\Sygnal HotPad\alerts.log`: `epoch <TAB> {GUID} <TAB> project <TAB> alerter`. The `{GUID}` is the desktop's stable id, formatted by `GuidToStr()` to match `Guid.ToString("B").ToUpper()` exactly (byte order matters — `Data1/2/3` little-endian, `Data4` sequential). The Sygnal **`notify`** skill writes these for Claude Code; a reference writer lives in [`.claude/skills/alert/`](.claude/skills/alert/). hotpad never writes the log — it only reads.
- **Resolution model.** A per-desktop "last visited" watermark is kept in `%APPDATA%\Sygnal HotPad\visits.ini` (`{GUID}=epoch`). An alert is **unresolved** iff it is *not* on the current desktop **and** its epoch is newer than that desktop's watermark. `MarkVisited()` stamps the current desktop's watermark on every desktop change (called from `TrackDesktopHistory`, gated on `AlertsEnabled`), so arriving at a desktop resolves its alerts and the desktop you're on never shows a dot.
- **GUID ↔ desktop number.** `GuidFromDesktopNum(n)` reads a desktop's GUID via the VD internals (`VD._GetDesktops_Obj().GetAt(n)` → `idx_GetId`); `BuildGuidNumMap()` builds the reverse map each render (desktops reorder).
- **Model + render.** `LoadAlertsModel(current)` parses the log, classifies/sorts (unresolved first, then newest), caps the list at 20, and fills `Alerts.List` + `Alerts.UnresByNum`. `RenderKeypad` draws the dot (`KpDot`) on flagged digit keys and, when the list is non-empty, a right-hand panel (the keypad stays centered; the panel widens the layered bitmap). Row rects are recorded in `Alerts.RowHits`; `HudClick` (an `OnMessage(WM_LBUTTONDOWN)` handler on the no-activate layered HUD) hit-tests a click and `VD.goToDesktopNum`s to jump. When `AlertsEnabled` is off, the model is cleared and nothing extra renders — identical to the pre-feature keypad.

The per-script sections below document the original scripts; their logic is what `virtual-combined.ahk` consolidates.

### Common Setup Pattern

Most scripts share a common initialization pattern:

```ahk
#SingleInstance force          ; Only one instance can run
ListLines 0                     ; Disable line logging for performance
SendMode "Input"                ; Faster, more reliable input method
SetWorkingDir A_ScriptDir       ; Consistent working directory
KeyHistory 0                    ; Disable key history for performance
#WinActivateForce              ; Force window activation
ProcessSetPriority "H"          ; High priority process
SetWinDelay -1                  ; No delay between window operations
SetControlDelay -1              ; No delay between control operations
```

## Scripts

### 1. app-specific-tab-switcher.ahk

**Purpose:** Replicates macOS Command+` functionality to switch between windows of the same application.

**Hotkeys:**
- `Alt + `` ` (backtick): Switch to next window of same app
- `Alt + Shift + `` ` (backtick): Switch to previous window of same app

**Key Functions:**

#### `SwitchToSameProcess(reverse := false)`
Lines: 38-99

The core switching logic that maintains window order consistency:

1. **Window Detection**: Gets active window ID and process name
2. **Array Management**: Maintains `prevArray` to track window order across invocations
3. **Order Preservation**: Keeps consistent forward/backward navigation even when windows are clicked out of order
4. **Wrap-around**: Cycles to beginning/end when reaching list boundaries

**Implementation Notes:**
- Uses `DetectHiddenWindows False` to prevent showing windows from other virtual desktops
- Tracks window order in global `prevArray` variable to maintain consistency
- Compares sorted arrays to detect when window list changes
- Filters out minimized windows and "PopupHost" windows

#### `GetProcessWindowsArray(search)`
Lines: 101-110

Returns an array of window handles for a given process, filtering:
- PopupHost windows (taskbar previews)
- Minimized windows

**Limitations:**
- Cannot detect when user clicks windows out of order (no window focus events)
- If you return to the original window after clicking around, it maintains the old order
- This is an acceptable trade-off to maintain consistent cycling behavior

---

### 2. virtual-move-window-with-desktop.ahk  *(merged & removed)*

> **Note:** This script no longer exists. Its move-and-follow behavior was merged into [virtual-move-window.ahk](virtual-move-window.ahk) (and now [virtual-combined.ahk](virtual-combined.ahk)) as a normalized follow path, with `Win + Ctrl + Shift + Left/Right` retained as an alias for the `Ctrl + Alt + Win + Left/Right` follow hotkeys. The description below is kept for historical context.

**Purpose:** Move the active window to adjacent virtual desktop and follow it.

**Hotkeys:**
- `Win + Ctrl + Shift + Left`: Move window to previous desktop and switch
- `Win + Ctrl + Shift + Right`: Move window to next desktop and switch

**Dependencies:**
- VD.ahk library (included from `../VD.ahk/VD.ah2`)

**Key Operations:**

#### Desktop Movement Logic
Lines: 31-53

1. Get current desktop number: `VD.getCurrentDesktopNum()`
2. Calculate target desktop with wrap-around
3. Capture active window handle: `WinExist("A")`
4. Switch to target desktop: `VD.goToDesktopNum()`
5. Move window to target: `VD.MoveWindowToDesktopNum()`
6. Reactivate window: `WinActivate()`

**Special Features:**
- Creates minimum 3 virtual desktops on startup: `VD.createUntil(3)`
- Wraps around desktop boundaries (first ↔ last)
- Attempts to hide "Malwarebytes Tray Application" to prevent unwanted window management

---

### 3. virtual-move-window.ahk

**Purpose:** Move the active window to adjacent virtual desktop WITHOUT following it.

**Hotkeys:**
- `Ctrl + Alt + Win + Right`: Move window to next desktop and follow
- `Ctrl + Alt + Win + Left`: Move window to previous desktop and follow
- `Alt + Win + Right`: Move window to next desktop (stay on current)
- `Alt + Win + Left`: Move window to previous desktop (stay on current)

**Key Difference from virtual-move-window-with-desktop.ahk:**

This script provides TWO modes of operation:
1. **With Follow** (`Ctrl+Alt+Win+Arrow`): Switches desktop after moving window
2. **Without Follow** (`Alt+Win+Arrow`): Leaves user on current desktop

Lines 76-78 and 91-93 have commented-out `VD.goToDesktopNum()` and `WinActivate()` calls, which is what prevents the desktop switch.

---

### 4. virtual-cascade.ahk

**Purpose:** Cascade, tile horizontally, or tile vertically all windows on the current virtual desktop.

**Hotkeys:**

Basic operations (all windows):
- `Win + Alt + V`: Tile all windows vertically
- `Win + Alt + H`: Tile all windows horizontally
- `Win + Alt + C`: Cascade all windows

Process-specific operations (add Shift):
- `Win + Alt + Shift + V`: Tile windows of same process vertically
- `Win + Alt + Shift + H`: Tile windows of same process horizontally
- `Win + Alt + Shift + C`: Cascade windows of same process

Utility hotkeys:
- `Win + Alt + Shift + NumpadAdd`: Bring all windows of current process to front
- `Win + Alt + Shift + NumpadSub`: Send all windows of current process to back

**Dependencies:**
- VD.ahk library
- [_winarrange.ahk](_winarrange.ahk) (local utility library)

**Configuration Constants:**
Lines: 31-37

```ahk
TILE         := 1                    ; WinArrange param for tiling
CASCADE      := 2                    ; WinArrange param for cascading
VERTICAL     := 0                    ; Vertical tiling arrangement
HORIZONTAL   := 1                    ; Horizontal tiling arrangement
ZORDER       := 4                    ; Cascade in Z-order
CLIENTAREA   := [50,50,1200,1000]    ; Not currently used
CA_MARGIN    := 50                   ; Margin around cascade/tile area
```

**Key Functions:**

#### `WinArrangeDesktop(arrangeType, arrangeOption, byProcess := false)`
Lines: 76-86

Main orchestration function:
1. Gets windows on current desktop (optionally filtered by process)
2. Calls WinArrange with appropriate parameters
3. Brings windows to front if process-specific

#### `GetCurrentDesktopWindows(byProcess := false)`
Lines: 98-136

**Critical function** that filters windows to only those on the current virtual desktop:

1. Temporarily enables `DetectHiddenWindows true` to see all windows
2. Gets all windows: `WinGetList()`
3. Filters by:
   - Process name (if `byProcess` is true)
   - Desktop number (using `VD.getDesktopNumOfWindow()`)
   - Not minimized (using `WinGetMinMax()`)
4. Returns array of window handles

**Why this matters:** Without proper filtering, the cascade/tile operations would affect windows on ALL virtual desktops, which would be disruptive.

#### `GetClientArea()`
Lines: 138-141

Calculates the usable screen area with margins:
- Gets primary monitor work area (excludes taskbar)
- Adds `CA_MARGIN` (50px) on all sides

#### `BringWindowsToFront(windows)`
Lines: 88-95

Moves windows to front in reverse order to maintain their relative positions.

---

### 5. _winarrange.ahk

**Purpose:** Low-level wrapper for Windows DLL functions that perform window arrangement.

**This is a utility library**, not a standalone script. It provides the core window arrangement functionality used by [virtual-cascade.ahk](extras/virtual-cascade.ahk).

**Key Function:**

#### `WinArrange(tileOrCascade, windowHandles, arrangeType, clientArea, mainWindow)`
Lines: 8-23

Wrapper for Windows API calls:
- `TileWindows()` - DLL function for tiling
- `CascadeWindows()` - DLL function for cascading

**Parameters:**
1. `tileOrCascade`: 1 for tile, 2 for cascade
2. `windowHandles`: Array of window handles (HWNDs)
3. `arrangeType`: Arrangement flags (vertical/horizontal/zorder)
4. `clientArea`: Array `[left, top, right, bottom]` defining arrangement boundary
5. `mainWindow`: Parent window handle (usually 0x0)

**Implementation Details:**

Uses `BufferFromArray()` helper to convert AutoHotKey arrays to C-style memory buffers that the DLL functions expect.

#### `BufferFromArray(arr, type)`
Lines: 25-36

Converts AutoHotKey array to memory buffer:
- `type` can be "Int" (4 bytes) or "Ptr" (pointer size)
- Allocates contiguous memory buffer
- Uses `NumPut()` to write each array element

**Historical Context:**

From comments (lines 3-6):
- Originally from 2010 AutoHotKey forums
- Updated to use non-deprecated AHK v2 calls
- Fixed "size" parameter handling for Win11 compatibility
- Window handles are now pointers (0x123abc format) vs old integer IDs

---

## Technical Details

### Virtual Desktop Integration

The VD.ahk library provides these key functions used across scripts:

- `VD.getCurrentDesktopNum()` - Get current desktop number (1-indexed)
- `VD.getCount()` - Get total number of desktops
- `VD.goToDesktopNum(num)` - Switch to desktop number
- `VD.MoveWindowToDesktopNum(hwnd, num)` - Move window to desktop
- `VD.getDesktopNumOfWindow(hwnd)` - Get window's desktop number
- `VD.createUntil(num)` - Ensure at least N desktops exist

### Window Filtering Strategy

Multiple scripts use sophisticated filtering to work only with relevant windows:

1. **Hidden Window Detection**: Toggle `DetectHiddenWindows` to control which windows are visible to the script
2. **Minimized Window Filtering**: Use `WinGetMinMax()` to exclude minimized windows (returns -1)
3. **Process Filtering**: Use `WinGetProcessName()` to filter by executable
4. **Desktop Filtering**: Use `VD.getDesktopNumOfWindow()` to filter by virtual desktop
5. **Window Class Filtering**: Exclude special windows like "PopupHost" (taskbar previews)

### Performance Optimizations

All scripts use these optimizations:

- `ProcessSetPriority "H"` - High priority for responsive hotkeys
- `SetWinDelay -1` - No artificial delays between operations
- `SetControlDelay -1` - No delays between control operations
- `ListLines 0` - Disable logging for performance
- `KeyHistory 0` - Disable key history logging

### Memory Management

The `_winarrange.ahk` library manually manages memory buffers to interface with C-style Windows API:

```ahk
buf := Buffer(totalSize)           ; Allocate memory
NumPut(type, val, buf, offset)     ; Write to memory
DllCall("Function", "Ptr", buf)    ; Pass to Windows API
```

This is necessary because AutoHotKey arrays cannot be directly passed to DLL functions.

---

## Usage Recommendations

### Recommended setup

Run **[hotpad.ahk](hotpad.ahk)** — it loads the consolidated [virtual-combined.ahk](virtual-combined.ahk) suite in-process (one tray icon) covering navigation, window moving (relative + numpad-absolute), and pinning. No need to launch the individual VD scripts.

[virtual-cascade.ahk](virtual-cascade.ahk) (window tiling/cascading) and [app-specific-tab-switcher.ahk](app-specific-tab-switcher.ahk) (app window cycling) are **not** part of the consolidated suite or startup; run them separately if you want them.

### Startup Configuration

To auto-start with Windows:

1. Create a shortcut to **[hotpad.ahk](hotpad.ahk)**
2. Press `Win+R` and type `shell:startup`
3. Move the shortcut to the Startup folder

### Hotkey Conflicts

Be aware of potential conflicts:

- Do **not** run `virtual-combined.ahk` (or `hotpad.ahk`) at the same time as the individual VD scripts it merges — they bind the same hotkeys and will fight. Exit the standalone instances first.
- The Numpad hotkeys assume **NumLock is ON** (they bind the digit keys `Numpad1`–`Numpad9`).
- Check for conflicts with other software using similar hotkey combinations.
- Hotkeys can be modified by editing the script files.

---

## Development Notes

### Code Quality

- All scripts properly updated to AHK v2.0 syntax
- Consistent error handling with try/catch blocks
- Extensive inline comments explaining complex logic
- Debug output available via `OutputDebug()` calls

### Known Limitations

1. **app-specific-tab-switcher.ahk**:
   - Cannot detect window focus changes without events
   - Order tracking can become inconsistent if user clicks windows randomly

2. **virtual-cascade.ahk**:
   - Sometimes windows need to be brought to front manually after arranging by process
   - Margin setting `CA_MARGIN` is hardcoded (can be edited)

3. **All Desktop Scripts**:
   - Require VD.ahk library to be in correct relative path (`../VD.ahk/VD.ah2`)
   - May need adjustment for multi-monitor setups

### Debugging

Enable debugging output:
- Check `OutputDebug()` calls in scripts
- Use DebugView or similar tool to view debug output
- Comment out `ListLines 0` to enable line logging

---

## File Reference

| File | Type | Purpose | Dependencies |
|------|------|---------|--------------|
| [hotpad.ahk](hotpad.ahk) | Entry point | Loads virtual-combined in-process; launches future standalone scripts | virtual-combined.ahk |
| [virtual-combined.ahk](virtual-combined.ahk) | Consolidated suite | Navigate + move (arrows & numpad) + pin + preview keypad + Config dialog (rename/settings/launchers) + operator-key app & Chrome launchers, one tray icon | VD.ahk, virtual-icon.ico, assets/keys/, gdiplus |
| [reference/virtual-navigate-wraparound.ahk](reference/virtual-navigate-wraparound.ahk) | reference/ (merged into combined) | Switch desktop with wrap-around | VD.ahk |
| [reference/virtual-move-window.ahk](reference/virtual-move-window.ahk) | reference/ (merged into combined) | Move window ± follow (arrows) | VD.ahk |
| [reference/virtual-numpad-desktops.ahk](reference/virtual-numpad-desktops.ahk) | reference/ (merged into combined) | Absolute desktop access 1–9 (navigate/move) | VD.ahk |
| [reference/virtual-pin-app.ahk](reference/virtual-pin-app.ahk) | reference/ (merged into combined) | Pin app/window to all desktops | VD.ahk |
| [reference/virtual-grid.ahk](reference/virtual-grid.ahk) | reference/ (merged into combined) | Ctrl+Win preview HUD + desktop rename | VD.ahk |
| [extras/virtual-cascade.ahk](extras/virtual-cascade.ahk) | extras/ (not in suite) | Cascade/tile windows | VD.ahk, _winarrange.ahk |
| [extras/_winarrange.ahk](extras/_winarrange.ahk) | extras/ library | Windows API wrapper | None |
| [extras/app-specific-tab-switcher.ahk](extras/app-specific-tab-switcher.ahk) | extras/ (not in suite) | App window cycling | None |
| [legacy/](legacy/) | legacy/ | Older/niche/personal scripts + notes (chrome-tab-search, key-detector, emoji-key, etc.) | — |
| [virtual-icon.ico](virtual-icon.ico) / [virtual-icon.svg](virtual-icon.svg) | Asset | Blue tray icon for the suite | None |
| [assets/keys/bs.png](assets/keys/bs.png) / `bs.svg` | Asset | Backspace key icon for the preview keypad | None |
| [assets/screenshots/keypad-hud.svg](assets/screenshots/keypad-hud.svg) | Asset (docs) | HUD reproduction used in the README | None |
| `%APPDATA%\Sygnal HotPad\settings.ini` | Config (per-machine, not in repo) | Persisted settings: `[Keypad] Scale`, and `[Launch_<id>]` per assigned operator key (`Action`/`Path`/`Args`/`Profile`/`Name`) | None |

---

## Hotkey Reference Table

> The Desktop Navigation, Window Movement, Numpad, Pinning, Preview keypad, Config dialog, and Launcher entries below are all provided by the consolidated [virtual-combined.ahk](virtual-combined.ahk).

### Desktop Navigation

| Hotkey | Action |
|--------|--------|
| `Ctrl + Win + ←` | Switch to previous desktop (wrap-around) |
| `Ctrl + Win + →` | Switch to next desktop (wrap-around) |

### Window Movement

| Hotkey | Action |
|--------|--------|
| `Ctrl + Alt + Win + ←/→` | Move window left/right + follow |
| `Ctrl + Win + Shift + ←/→` | Move window left/right + follow (alias) |
| `Alt + Win + ←/→` | Move window left/right (stay) |

### Numpad (absolute desktop access, NumLock ON)

| Hotkey | Action |
|--------|--------|
| `Ctrl + Win + Numpad1…9` | Switch directly to desktop 1–9 |
| `Ctrl + Win + Numpad0` | Switch directly to desktop 10 |
| `Ctrl + Alt + Win + Numpad0…9` | Move window to that desktop (1–10) + follow |
| `Alt + Win + Numpad0…9` | Move window to that desktop (1–10), stay |

### Pinning

| Hotkey | Action |
|--------|--------|
| `Ctrl + Win + Z` | Pin/unpin active app (all its windows) to every desktop |
| `Ctrl + Win + X` | Pin/unpin only the active window to every desktop |

### Preview keypad & Config dialog

| Hotkey / action | Result |
|-----------------|--------|
| `Ctrl + Win` (hold) | Show the numpad keypad HUD (desktops 1–10, current highlighted, names; operator keys show their launcher names, `.` shows "Config") on the primary monitor; release to dismiss. With **desktop alerts** on, also shows a yellow dot on desktops with unaddressed alerts + a clickable alert list (click to jump) |
| `Ctrl + Win + NumpadDot` | Open the Config dialog (Desktop / Settings / Launchers tabs); also `NumpadDel` for NumLock-off |
| Tray icon → **Settings** / **Launchers** | Open the Config dialog on that tab (keypad size + desktop-alerts toggle; per-key launchers). Persisted to `%APPDATA%\Sygnal HotPad\settings.ini` |

### Launchers (Ctrl+Win + operator keys, configurable)

| Hotkey | Action |
|--------|--------|
| `Ctrl + Win + /` | Default: open the Chrome profile menu (new window on the current desktop) |
| `Ctrl + Win + + − * = ( ) Enter` | Run the assigned app, or open Chrome with the assigned profile — set in Config → Launchers |

### Window Arrangement

| Hotkey | Action |
|--------|--------|
| `Win + Alt + V` | Tile all windows vertically |
| `Win + Alt + H` | Tile all windows horizontally |
| `Win + Alt + C` | Cascade all windows |
| `Win + Alt + Shift + V` | Tile same-app windows vertically |
| `Win + Alt + Shift + H` | Tile same-app windows horizontally |
| `Win + Alt + Shift + C` | Cascade same-app windows |

### Window Switching

| Hotkey | Action |
|--------|--------|
| ``Alt + ` `` | Switch to next window of same app |
| ``Alt + Shift + ` `` | Switch to previous window of same app |

### Utility

| Hotkey | Action |
|--------|--------|
| `Win + Alt + Shift + NumpadAdd` | Bring same-app windows to front |
| `Win + Alt + Shift + NumpadSub` | Send same-app windows to back |

---

## API Reference

### Windows DLL Functions Used

#### TileWindows
```c
WORD TileWindows(
  HWND hwndParent,      // Parent window (usually NULL)
  UINT wHow,            // Tiling flags (HORIZONTAL/VERTICAL)
  LPCRECT lpRect,       // Bounding rectangle
  UINT cKids,           // Number of windows
  const HWND *lpKids    // Array of window handles
);
```

#### CascadeWindows
```c
WORD CascadeWindows(
  HWND hwndParent,      // Parent window (usually NULL)
  UINT wHow,            // Cascade flags (usually 0 or ZORDER)
  LPCRECT lpRect,       // Bounding rectangle
  UINT cKids,           // Number of windows
  const HWND *lpKids    // Array of window handles
);
```

### AutoHotKey Functions Used

Key window management functions:
- `WinGetList([WinTitle, ...])` - Get array of window handles
- `WinExist([WinTitle, ...])` - Get handle of matching window
- `WinActivate([WinTitle, ...])` - Activate window
- `WinGetProcessName([WinTitle, ...])` - Get process name
- `WinGetTitle([WinTitle, ...])` - Get window title
- `WinGetClass([WinTitle, ...])` - Get window class
- `WinGetMinMax([WinTitle, ...])` - Get minimized/maximized state
- `WinMoveTop([WinTitle, ...])` - Move window to top of Z-order
- `WinMoveBottom([WinTitle, ...])` - Move window to bottom of Z-order
- `DetectHiddenWindows(Mode)` - Control hidden window detection
- `MonitorGetWorkArea(N, &Left, &Top, &Right, &Bottom)` - Get monitor dimensions

---

## Contributing

When modifying these scripts:

1. Maintain the common initialization pattern
2. Add inline comments for complex logic
3. Use consistent naming conventions (camelCase for functions, UPPERCASE for constants)
4. Test with multiple virtual desktops and multiple monitors
5. Consider performance implications of window enumeration
6. Update this documentation with changes

---

## Credits

- **virtual-move-window scripts**: Based on [StackOverflow answer by multiple contributors](https://superuser.com/questions/1685845/moving-current-window-to-another-desktop-in-windows-11-using-shortcut-keys)
- **_winarrange.ahk**: Based on [ancient AutoHotKey forum post](https://www.autohotkey.com/board/topic/80580-how-to-programmatically-tile-cascade-windows/), updated for AHK v2 and Win11
- **app-specific-tab-switcher.ahk**: Original implementation inspired by macOS Command+` functionality
- **VD.ahk library**: Created by [FuPeiJiang](https://github.com/FuPeiJiang/VD.ahk)

---

## License

These scripts are provided as-is for use with AutoHotKey v2.0. See individual script headers for specific attribution and licensing information.
