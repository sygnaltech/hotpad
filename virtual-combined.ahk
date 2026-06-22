; =============================================================================
; virtual-combined.ahk
; Consolidated virtual-desktop suite - runs as ONE process / ONE tray icon.
;
; Merged from (originals kept in repo, but no longer launched individually):
;   - virtual-navigate-wraparound.ahk
;   - virtual-move-window.ahk
;   - virtual-numpad-desktops.ahk
;   - virtual-pin-app.ahk
;
; Hotkeys ( ^ = Ctrl   ! = Alt   # = Win   + = Shift ):
;   Navigate (wrap-around):   Ctrl+Win+Left/Right
;   Navigate (absolute):      Ctrl+Win+Numpad1..9
;   Move window + follow:     Ctrl+Alt+Win+Left/Right   (alias: Ctrl+Win+Shift+Left/Right)
;   Move window + follow:     Ctrl+Alt+Win+Numpad1..9
;   Move window + stay:       Alt+Win+Left/Right
;   Move window + stay:       Alt+Win+Numpad1..9
;   Pin app to all desktops:  Ctrl+Win+Z
;   Pin window to all desktops: Ctrl+Win+X
;   Preview grid (hold):      Ctrl+Win            (numpad-layout HUD of desktops 1-9)
;   Rename current desktop:   Ctrl+Win+NumpadDot  (uses native Win11 names)
;
; NOTE: the Numpad hotkeys assume NumLock is ON (they bind the digit keys).
; =============================================================================

;#SETUP START
#SingleInstance force
ListLines 0
SendMode "Input" ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir A_ScriptDir ; Ensures a consistent starting directory.
KeyHistory 0
#WinActivateForce

ProcessSetPriority "H"

SetWinDelay -1
SetControlDelay -1

; Include the virtual desktop helper library (exactly once).
#Include lib/VD.ah2

; You should WinHide invisible programs that have a window.
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

; ---- Preview-grid config + state --------------------------------------------
; Held in a class so it's reliably accessible from every function. Defined before
; the auto-execute body so its static init isn't flagged as unreachable.
class VirtualGrid {
    ; Keypad geometry (px) - tweak here.
    static Pad  := 18           ; outer padding
    static Cell := 80           ; key size
    static Gap  := 12           ; gap between keys

    ; Colors (ARGB 0xAARRGGBB).
    static ColBody    := 0xFF3A3A3A  ; body + key fill
    static ColStroke  := 0xFF808080  ; key border
    static ColCur     := 0xFF1E90FF  ; current desktop key fill (tray-icon blue)
    static ColCurStrk := 0xFF5CB0FF  ; current desktop key border
    static ColTxt     := 0xFFD6D6D6  ; key glyph / number
    static ColCurTxt  := 0xFFFFFFFF
    static ColName    := 0xFF9AA0A6  ; desktop name
    static ColCurName := 0xFFEAF4FF
    static ColAlert   := 0xFFFFC400  ; unresolved-alert dot (amber/yellow)
    static ColPanel   := 0xFF2E2E2E  ; alert list panel background

    ; Persisted settings (loaded from the config file at startup).
    static Scale := 1.0         ; keypad scale: 1.0 / 1.5 / 2.0 = Small / Medium / Large

    ; Runtime state.
    static Hud := 0             ; the layered Gui while created (kept hidden when not shown)
    static ShownFor := -1       ; which desktop the shown keypad highlights
    static Naming := false      ; true while the rename box is open (suppresses the HUD)
    static GdipToken := 0       ; GDI+ token (started once at init)
    static HudPx := 0           ; screen-x of the shown HUD bitmap (for click hit-testing)
    static HudPy := 0           ; screen-y of the shown HUD bitmap
}

; Desktop back-stack ("browser back" for virtual desktops). The poll in CheckChord
; records each desktop you leave; Ctrl+Win+Backspace walks back through it.
class VirtualBack {
    static Stack := []          ; desktops you've left, oldest first, newest last
    static Last := 0            ; last-seen current desktop (0 = uninitialized)
    static GoingBack := false   ; true while a back-nav is in flight (don't re-record it)
    static Max := 10            ; how many steps of history to keep
}

; Configurable operator-key launchers (see the LAUNCHER section for the logic).
; Defined up here with the other classes so its static init isn't flagged as
; unreachable code after the auto-execute return.
class LaunchCfg {
    static Items := Map()   ; id -> {action:"app"|"chrome"|"none", path, args, profile}
}

; ---- Alert state (desktop-aware notifications) ------------------------------
; Alerts are appended to %APPDATA%\Sygnal HotPad\alerts.log by the `alert` skill
; (one tab-delimited line: epoch <TAB> {GUID} <TAB> project <TAB> alerter). An
; alert is "unresolved" until you visit the desktop it fired on; visiting stamps a
; per-desktop watermark in visits.ini. See the ALERTS section for the logic.
class Alerts {
    static Visits := Map()       ; "{GUID}" -> epoch seconds last visited
    static List := []            ; current display model (newest/unresolved first, cap 20)
    static UnresByNum := Map()   ; current desktop number -> true if it has an unresolved alert
    static RowHits := []         ; [{x1,y1,x2,y2,num}] list-row rects, bitmap-relative, for clicks
    static LoadedVisits := false ; lazy-load guard for visits.ini
}

; ---- Init (auto-execute section) -------------------------------------------
; Distinct tray icon + tooltip so the single combined process is identifiable.
; A_ScriptDir is the entry script's dir (works whether run directly or #Included
; from startup.ahk, since both live alongside virtual-icon.ico).
TraySetIcon A_ScriptDir "\virtual-icon.ico"
A_IconTip := "Sygnal HotPad"

VD.createUntil(3) ; Create until we have at least 3 virtual desktops

; Start GDI+ once for the preview-keypad renderer.
DllCall("LoadLibrary", "Str", "gdiplus")
gdipSi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
NumPut("UInt", 1, gdipSi, 0)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdipTok := 0, "Ptr", gdipSi, "Ptr", 0)
VirtualGrid.GdipToken := gdipTok

; Load persisted settings, and add a "Settings" entry to the tray right-click menu.
LoadConfig()
LoadLaunchers()
A_TrayMenu.Insert("1&", "Launchers", (*) => ShowHotpadDialog("launchers"))
A_TrayMenu.Insert("1&", "Settings", (*) => ShowHotpadDialog("settings"))
A_TrayMenu.Insert("3&")

; The Numpad hotkeys are registered at runtime, so this loop MUST run in the
; auto-execute section (before the first `return`/hotkey label) or they won't bind.
; Numpad1..9 -> desktops 1..9; Numpad0 -> desktop 10.
Loop 10 {
    n := A_Index = 10 ? 0 : A_Index   ; the key digit (0 for the 10th)
    d := A_Index                      ; the desktop number (1..10)
    Hotkey "^#Numpad" n, NavigateAbsoluteClosure(d)    ; Ctrl+Win+N       -> switch to desktop d
    Hotkey "^!#Numpad" n, MoveAbsoluteFollowClosure(d) ; Ctrl+Alt+Win+N   -> move window to d + follow
    Hotkey "!#Numpad" n, MoveAbsoluteStayClosure(d)    ; Alt+Win+N        -> move window to d, stay
}

; Bind the configurable operator-key launchers from the saved config.
ApplyLaunchers()

; Poll for the Ctrl+Win chord that shows the preview grid (robust, and never
; interferes with the modifier-based hotkeys above).
SetTimer CheckChord, 75

return

; =============================================================================
; HOTKEY LABELS (arrows, pin)
; =============================================================================

; --- Navigate desktops (wrap-around) ---
^#Left::  VD.goToDesktopNum(AdjacentDesktop(-1))
^#Right:: VD.goToDesktopNum(AdjacentDesktop(1))

; --- Move active window between desktops ---
^!#Right:: MoveActiveAdjacent(1, true)    ; follow
^!#Left::  MoveActiveAdjacent(-1, true)
^#+Right:: MoveActiveAdjacent(1, true)    ; alias for follow
^#+Left::  MoveActiveAdjacent(-1, true)
!#Right::  MoveActiveAdjacent(1, false)   ; stay
!#Left::   MoveActiveAdjacent(-1, false)

; --- Pin apps / windows to all desktops ---
^#z::PinActiveApp()
^#x::PinActiveWindow()

; --- Desktop / Settings dialog (Ctrl+Win + decimal point) ---
; Opens on the Desktop (rename) tab. NumpadDot = NumLock on, NumpadDel = off.
^#NumpadDot:: ShowHotpadDialog("desktop")
^#NumpadDel:: ShowHotpadDialog("desktop")

; --- Go back to the previous desktop (Ctrl+Win + Backspace) ---
; No `~`, so the keypress is consumed (suppresses the default Windows action).
; If your numpad's BS key sends a different code, run legacy/key-detector.ahk to
; find it and change the key name below.
^#Backspace:: GoBackDesktop()

; --- Configurable launcher keys (Ctrl+Win + operator keys) ---
; The operator keys (+ - * / Enter = ( ) ) are bound dynamically from the saved
; config by ApplyLaunchers() in the auto-execute section above — see the LAUNCHER
; section near the Chrome helpers. By default "/" opens the Chrome profile menu.

; =============================================================================
; CLOSURE FACTORIES (for the runtime-registered Numpad hotkeys)
; Each call creates a fresh scope so the captured desktop number is correct
; (avoids the classic "all hotkeys see the final loop value" bug).
; =============================================================================
NavigateAbsoluteClosure(n)   => (*) => NavigateAbsolute(n)
MoveAbsoluteFollowClosure(n) => (*) => MoveActiveAbsolute(n, true)
MoveAbsoluteStayClosure(n)   => (*) => MoveActiveAbsolute(n, false)

; =============================================================================
; APP LAUNCH
; =============================================================================

; ---- Configurable operator-key launchers -----------------------------------
; Each operator key on the keypad (Ctrl+Win + + - * / Enter = ( ) ) can be
; assigned to launch an app, or Chrome with a chosen profile. Assignments live in
; the INI ([Launch_<id>] sections) and are edited from the Settings dialog.

; The bindable operator keys. glyph = shown in the UI/HUD; keys = every AHK hotkey
; string to bind for it (numpad + main row where both exist and are nameable;
; main-row * and + are omitted because they collide with AHK's wildcard/Shift
; syntax, so the numpad versions cover them).
LauncherDefs() {
    return [
        {id:"div",    glyph:"/",     keys:["^#NumpadDiv", "^#/"]},
        {id:"mult",   glyph:"*",     keys:["^#NumpadMult"]},
        {id:"sub",    glyph:"−",     keys:["^#NumpadSub", "^#-"]},
        {id:"add",    glyph:"+",     keys:["^#NumpadAdd"]},
        {id:"enter",  glyph:"Enter", keys:["^#NumpadEnter"]},
        {id:"eq",     glyph:"=",     keys:["^#="]},
        {id:"lparen", glyph:"(",     keys:["^#("]},
        {id:"rparen", glyph:")",     keys:["^#)"]},
    ]
}

; Read launcher assignments from the INI. The first time (before any save), seed
; the "/" key to the Chrome profile menu so the prior Chrome-on-/ still works.
LoadLaunchers() {
    f := ConfigFile()
    seeded := IniRead(f, "Launchers", "Seeded", "")
    LaunchCfg.Items := Map()
    for d in LauncherDefs() {
        sec := "Launch_" d.id
        action := IniRead(f, sec, "Action", "")
        if (action = "") {
            if (!seeded && d.id = "div")   ; default seed
                LaunchCfg.Items[d.id] := {action:"chrome", path:"", args:"", profile:"ask", name:"Chrome"}
            continue
        }
        LaunchCfg.Items[d.id] := {action: action, path: IniRead(f, sec, "Path", ""), args: IniRead(f, sec, "Args", ""), profile: IniRead(f, sec, "Profile", "ask"), name: IniRead(f, sec, "Name", "")}
    }
}

; Persist the given assignments (id -> object), then re-bind the hotkeys.
SaveLaunchers(items) {
    f := ConfigFile()
    dir := A_AppData "\Sygnal HotPad"
    if !DirExist(dir)
        DirCreate(dir)
    for d in LauncherDefs() {
        sec := "Launch_" d.id
        if (items.Has(d.id) && items[d.id].action != "" && items[d.id].action != "none") {
            e := items[d.id]
            IniWrite(e.action, f, sec, "Action")
            IniWrite(e.HasOwnProp("path")    ? e.path    : "", f, sec, "Path")
            IniWrite(e.HasOwnProp("args")    ? e.args    : "", f, sec, "Args")
            IniWrite(e.HasOwnProp("profile") ? e.profile : "ask", f, sec, "Profile")
            IniWrite(e.HasOwnProp("name")    ? e.name    : "", f, sec, "Name")
        } else {
            try IniDelete(f, sec)
        }
    }
    IniWrite(1, f, "Launchers", "Seeded")
    LaunchCfg.Items := items
    ApplyLaunchers()
    VirtualGrid.ShownFor := -1   ; force the HUD to rebuild with any changed names
}

; (Re)bind every operator hotkey to match the current config. Assigned keys are
; turned On; everything else is bound disabled (Off) so a re-save can clear them.
ApplyLaunchers() {
    for d in LauncherDefs() {
        e := LaunchCfg.Items.Has(d.id) ? LaunchCfg.Items[d.id] : 0
        on := e && e.action != "" && e.action != "none"
        handler := LauncherClosure(d.id)
        for k in d.keys
            try Hotkey(k, handler, on ? "On" : "Off")
    }
}

LauncherClosure(id) => (*) => RunLauncher(id)

; Fire the launcher assigned to operator key `id`.
RunLauncher(id) {
    if !LaunchCfg.Items.Has(id)
        return
    e := LaunchCfg.Items[id]
    if (e.action = "chrome") {
        if (e.profile = "ask" || e.profile = "")
            ChromeMenu()
        else
            LaunchChromeProfile(e.profile)
    } else if (e.action = "app") {
        if (e.path = "")
            return
        try
            Run('"' e.path '" ' e.args)
        catch as err
            MsgBox "Couldn't launch:`n" e.path "`n`n" err.Message, "Sygnal HotPad", "Icon!"
    }
}

; Why a menu instead of Chrome's own picker:
; Launching `chrome.exe --new-window` with NO profile shows Chrome's profile
; picker. Picking a profile there does NOT honor --new-window — Chrome activates
; that profile's existing window (yanking you to whatever virtual desktop it lives
; on) and just adds a tab. So we pick the profile ourselves and launch with it
; pinned: `chrome.exe --profile-directory="Profile X" --new-window`. With the
; profile specified the picker never appears and --new-window is honored, so a
; brand-new window opens on the CURRENT desktop.
;
; The menu lists each Chrome profile by its folder name (Default, Profile 1, …),
; read live from disk so it works as-is on any machine.

; Build the profile menu once (profiles rarely change; restart to refresh).
ChromeMenu() {
    static m := BuildChromeMenu()
    m.Show()
}

BuildChromeMenu() {
    m := Menu()
    dirs := ChromeProfileDirs()
    for d in dirs
        m.Add(d, ChromeProfileClosure(d))
    if (dirs.Length = 0)   ; no profiles found -> a single "new window" entry
        m.Add("New Chrome window", ChromeProfileClosure(""))
    return m
}

; The live Chrome profile folder names (Default, Profile 1, …), read from disk so
; the menu and the Settings profile dropdown stay in sync on any machine.
ChromeProfileDirs() {
    dirs := []
    base := EnvGet("LocalAppData") "\Google\Chrome\User Data"
    Loop Files base "\*", "D" {
        if (A_LoopFileName = "Default" || RegExMatch(A_LoopFileName, "^Profile \d+$"))
            dirs.Push(A_LoopFileName)
    }
    return dirs
}

ChromeProfileClosure(dir) => (*) => LaunchChromeProfile(dir)

; Open `dir`'s profile in a NEW window on the current desktop (blank dir = let
; Chrome use its default/last profile, still in a new window).
LaunchChromeProfile(dir) {
    exe := ChromePath()
    if (exe = "") {
        MsgBox "Couldn't find Chrome — is it installed?", "Sygnal HotPad", "Icon!"
        return
    }
    prof := (dir = "") ? "" : '--profile-directory="' dir '" '
    Run '"' exe '" ' prof '--new-window'
}

; Resolve chrome.exe: App Paths registration first (robust, even off PATH), then
; the usual install locations. Returns "" if not found.
ChromePath() {
    try
        return RegRead("HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe")
    for path in [ A_ProgramFiles "\Google\Chrome\Application\chrome.exe"
                , EnvGet("ProgramFiles(x86)") "\Google\Chrome\Application\chrome.exe"
                , EnvGet("LocalAppData") "\Google\Chrome\Application\chrome.exe" ]
        if FileExist(path)
            return path
    return ""
}

; =============================================================================
; NAVIGATION
; =============================================================================

; Return the next/previous desktop number, wrapping around the ends.
; direction: 1 = next, -1 = previous.
AdjacentDesktop(direction) {
    current := VD.getCurrentDesktopNum()
    total := VD.getCount()
    if (direction > 0)
        return (current = total) ? 1 : current + 1
    return (current = 1) ? total : current - 1
}

; Switch directly to a numbered desktop, creating it if it doesn't exist yet.
NavigateAbsolute(target) {
    VD.createUntil(target)
    VD.goToDesktopNum(target)
}

; Record desktop changes into the back-stack. Runs from CheckChord every 75ms, so
; it catches switches made any way (our hotkeys, native gestures, Task View, etc.).
TrackDesktopHistory() {
    cur := VD.getCurrentDesktopNum()
    if (cur = VirtualBack.Last)
        return
    if (VirtualBack.GoingBack) {
        VirtualBack.GoingBack := false        ; this change was the back-nav itself; don't record
    } else if (VirtualBack.Last != 0) {
        VirtualBack.Stack.Push(VirtualBack.Last)
        while (VirtualBack.Stack.Length > VirtualBack.Max)
            VirtualBack.Stack.RemoveAt(1)     ; drop the oldest beyond the cap
    }
    VirtualBack.Last := cur
    MarkVisited(cur)   ; arriving at a desktop resolves its alerts (stamps the watermark)
}

; "Browser back" for desktops: return to the most recent one you came from.
GoBackDesktop() {
    if (VirtualBack.Stack.Length < 1)
        return
    target := VirtualBack.Stack.Pop()
    VirtualBack.GoingBack := true
    VD.goToDesktopNum(target)
}

; =============================================================================
; MOVING WINDOWS
; =============================================================================

; Move the active window to an adjacent desktop (relative, wrap-around).
MoveActiveAdjacent(direction, follow) {
    hwnd := WinExist("A")
    if (!hwnd) ; nothing focused (e.g. desktop itself) - bail
        return
    MoveWindowToDesktop(hwnd, AdjacentDesktop(direction), follow)
}

; Move the active window to a numbered desktop (absolute), creating it if needed.
MoveActiveAbsolute(target, follow) {
    hwnd := WinExist("A")
    if (!hwnd)
        return
    VD.createUntil(target)
    MoveWindowToDesktop(hwnd, target, follow)
}

; Shared move logic: move the window first (while stable on this desktop), then
; optionally follow it. follow=true switches to the target desktop and reactivates.
MoveWindowToDesktop(hwnd, target, follow) {
    VD.MoveWindowToDesktopNum("ahk_id " hwnd, target)
    if (follow) {
        VD.goToDesktopNum(target)
        WaitForDesktop(target) ; the switch is async - wait for it to actually land
        try WinActivate("ahk_id " hwnd) ; best-effort: a miss is harmless
    }
}

; Poll until the active desktop is the target (or we time out ~200ms).
; goToDesktopNum returns before the switch completes, so a window moved there
; is briefly unaddressable; activating it too early throws "target not found".
WaitForDesktop(target) {
    Loop 20 {
        if (VD.getCurrentDesktopNum() = target)
            return
        Sleep 10
    }
}

; =============================================================================
; PINNING (to all virtual desktops)
; =============================================================================

PinActiveApp() {
    hwnd := WinExist("A")
    if !hwnd {
        ShowTransientTooltip("No active window detected.")
        return
    }

    exePath := ""
    try exePath := WinGetProcessPath("ahk_id " hwnd)
    catch {
        ShowTransientTooltip("Unable to find process for active window.")
        return
    }

    if !exePath {
        ShowTransientTooltip("Unable to find process for active window.")
        return
    }

    try {
        if VD.IsExePinned(exePath) {
            VD.UnPinExe(exePath)
            ShowTransientTooltip("Unpinned app from all desktops.")
        } else {
            VD.PinExe(exePath)
            ShowTransientTooltip("Pinned app to all desktops.")
        }
    } catch as err {
        OutputDebug("PinActiveApp error: " err.Message)
        ShowTransientTooltip("Failed to pin app.")
    }
}

PinActiveWindow() {
    hwnd := WinExist("A")
    if !hwnd {
        ShowTransientTooltip("No active window detected.")
        return
    }

    wintitle := "ahk_id " hwnd

    try {
        isPinned := VD.IsWindowPinned(wintitle)
        if (isPinned = -1) {
            ShowTransientTooltip("Unable to access the active window.")
            return
        }

        if isPinned {
            VD.UnPinWindow(wintitle)
            ShowTransientTooltip("Unpinned window from all desktops.")
        } else {
            VD.PinWindow(wintitle)
            ShowTransientTooltip("Pinned window to all desktops.")
        }
    } catch as err {
        OutputDebug("PinActiveWindow error: " err.Message)
        ShowTransientTooltip("Failed to pin window.")
    }
}

ShowTransientTooltip(message, duration := 1200) {
    ToolTip message
    SetTimer(() => ToolTip(), -duration)
}

; =============================================================================
; PREVIEW GRID (hold Ctrl+Win) + DESKTOP RENAME
; =============================================================================

ChordHeld() {
    return GetKeyState("Control", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
}

CheckChord() {
    TrackDesktopHistory()
    if VirtualGrid.Naming
        return
    if ChordHeld()
        ShowOrUpdateGrid()
    else
        HideGrid()
}

; Backed by the combined dialog now (kept as a named entry point).
RenameCurrentDesktop() => ShowHotpadDialog("desktop")

; The desktop's custom name, or "" if it has none (so we don't print a redundant
; "Desktop N" under the number).
DesktopName(n) {
    name := VD.getNameFromDesktopNum(n)
    try {
        if (name = VD._getLocalizedWord_Desktop() " " n)
            return ""
    }
    return name
}

ShowOrUpdateGrid() {
    current := VD.getCurrentDesktopNum()

    ; Already showing and highlight is current -> nothing to do.
    if (VirtualGrid.Hud && VirtualGrid.ShownFor = current)
        return

    s := VirtualGrid.Scale
    pad := Round(VirtualGrid.Pad * s), cell := Round(VirtualGrid.Cell * s), gap := Round(VirtualGrid.Gap * s)
    kpW := pad*2 + 4*cell + 3*gap
    kpH := pad*2 + 5*cell + 4*gap

    ; Build the alert model for this desktop (dots + list). When there are alerts,
    ; a panel hangs off the right of the keypad; the keypad itself stays centered.
    LoadAlertsModel(current)
    showPanel := Alerts.List.Length > 0
    panelGap := showPanel ? Round(16 * s) : 0
    panelW   := showPanel ? Round(320 * s) : 0
    panelX   := kpW + panelGap
    totalW   := kpW + panelGap + panelW

    pBmp := RenderKeypad(current, pad, cell, gap, s, kpW, kpH, totalW, panelX, panelW, showPanel)

    ; Create the layered, no-activate, always-on-top window once; reuse it after.
    if !VirtualGrid.Hud {
        g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x80000 +E0x08000000") ; 0x80000=WS_EX_LAYERED, 0x08000000=WS_EX_NOACTIVATE
        g.Show("NoActivate Hide")
        VirtualGrid.Hud := g
        OnMessage(0x201, HudClick)   ; WM_LBUTTONDOWN -> click an alert row to jump
    }

    MonitorGet(MonitorGetPrimary(), &mLeft, &mTop, &mRight, &mBottom)
    ; Center the KEYPAD on the primary monitor; the panel extends to its right.
    px := mLeft + ((mRight - mLeft) - kpW) // 2
    py := mTop + ((mBottom - mTop) - kpH) // 2
    VirtualGrid.HudPx := px, VirtualGrid.HudPy := py

    KpBlitLayered(VirtualGrid.Hud.Hwnd, pBmp, px, py, totalW, kpH)
    DllCall("ShowWindow", "Ptr", VirtualGrid.Hud.Hwnd, "Int", 8) ; SW_SHOWNA = show without activating
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)

    VirtualGrid.ShownFor := current
}

; Click handler for the HUD: if the press lands on an alert row, jump to its desktop.
; The HUD is layered + no-activate, but its opaque pixels still receive button-downs.
HudClick(wParam, lParam, msg, hwnd) {
    if (!VirtualGrid.Hud || hwnd != VirtualGrid.Hud.Hwnd || VirtualGrid.ShownFor = -1)
        return
    MouseGetPos(&mx, &my)
    rx := mx - VirtualGrid.HudPx, ry := my - VirtualGrid.HudPy
    for h in Alerts.RowHits {
        if (rx >= h.x1 && rx <= h.x2 && ry >= h.y1 && ry <= h.y2) {
            if (h.num > 0)
                VD.goToDesktopNum(h.num)   ; arriving stamps the visit -> resolves it
            return
        }
    }
}

HideGrid() {
    if !VirtualGrid.Hud
        return
    DllCall("ShowWindow", "Ptr", VirtualGrid.Hud.Hwnd, "Int", 0) ; SW_HIDE
    VirtualGrid.ShownFor := -1
}

; ---- Keypad rendering (GDI+) ------------------------------------------------
; Numpad layout. k=kind: digit|glyph|text|icon. d=desktop (digit). lbl overrides
; the drawn label (the 0 key shows "0" but is desktop 10). c/r=col/row, cs/rs=spans.
; lid = launcher id (operator keys); its assigned name is drawn under the glyph.
; name = a fixed caption drawn under the glyph (the . key always shows "Config").
KpLayout() {
    return [
        {k:"glyph", t:"=",        lid:"eq",   c:0, r:0},
        {k:"glyph", t:"/",        lid:"div",  c:1, r:0},
        {k:"glyph", t:"*",        lid:"mult", c:2, r:0},
        {k:"icon",  ic:"assets\keys\bs.png", c:3, r:0},
        {k:"digit", d:7,          c:0, r:1},
        {k:"digit", d:8,          c:1, r:1},
        {k:"digit", d:9,          c:2, r:1},
        {k:"glyph", t:"−", sz:34, lid:"sub", c:3, r:1},
        {k:"digit", d:4,          c:0, r:2},
        {k:"digit", d:5,          c:1, r:2},
        {k:"digit", d:6,          c:2, r:2},
        {k:"glyph", t:"+", sz:34, lid:"add", c:3, r:2},
        {k:"digit", d:1,          c:0, r:3},
        {k:"digit", d:2,          c:1, r:3},
        {k:"digit", d:3,          c:2, r:3},
        {k:"text",  t:"Enter", sz:20, lid:"enter", c:3, r:3, rs:2},
        {k:"digit", d:10, lbl:"0", c:0, r:4, cs:2},
        {k:"glyph", t:".", sz:34, name:"Config", c:2, r:4},
    ]
}

; The caption to draw under an operator/glyph key: a fixed name (the . key), or
; the name assigned to its launcher (only when that key is actually assigned).
KpKeyName(kd) {
    if kd.HasOwnProp("name")
        return kd.name
    if (kd.HasOwnProp("lid") && LaunchCfg.Items.Has(kd.lid)) {
        e := LaunchCfg.Items[kd.lid]
        if (e.action != "" && e.action != "none" && e.HasOwnProp("name"))
            return e.name
    }
    return ""
}

RenderKeypad(current, pad, cell, gap, s, kpW, kpH, totalW := 0, panelX := 0, panelW := 0, showPanel := false) {
    count := VD.getCount()
    if (totalW = 0)
        totalW := kpW

    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", totalW, "Int", kpH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBmp, "Ptr*", &G := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", G, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", G, "Int", 4)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", G, "Int", 7)

    KpFill(G, 0, 0, kpW, kpH, 22*s, VirtualGrid.ColBody)

    for kd in KpLayout() {
        cs := kd.HasOwnProp("cs") ? kd.cs : 1
        rs := kd.HasOwnProp("rs") ? kd.rs : 1
        kx := pad + kd.c * (cell + gap)
        ky := pad + kd.r * (cell + gap)
        kw := cell + (cs - 1) * (cell + gap)
        kh := cell + (rs - 1) * (cell + gap)

        isCur := (kd.k = "digit" && kd.d = current)
        KpFill(G, kx, ky, kw, kh, 10*s, isCur ? VirtualGrid.ColCur : VirtualGrid.ColBody)
        KpStroke(G, kx, ky, kw, kh, 10*s, isCur ? VirtualGrid.ColCurStrk : VirtualGrid.ColStroke, 1.5*s)

        if (kd.k = "digit") {
            nm := (kd.d <= count) ? DesktopName(kd.d) : ""
            txtCol := isCur ? VirtualGrid.ColCurTxt : VirtualGrid.ColTxt
            lbl := kd.HasOwnProp("lbl") ? kd.lbl : kd.d
            ; Number always sits in the upper area, name slot reserved below.
            KpText(G, lbl, kx, ky + 6*s, kw, kh - 30*s, 30*s, txtCol, true)
            if (nm != "")
                KpText(G, nm, kx, ky + kh - 30*s, kw, 24*s, 12*s, isCur ? VirtualGrid.ColCurName : VirtualGrid.ColName)
            ; Yellow dot, top-left of the key, when this desktop has an unresolved alert.
            if (Alerts.UnresByNum.Has(kd.d))
                KpDot(G, kx + 16*s, ky + 18*s, 6*s, VirtualGrid.ColAlert)
        } else if (kd.k = "glyph" || kd.k = "text") {
            sz := kd.HasOwnProp("sz") ? kd.sz : 30
            nm := KpKeyName(kd)
            if (nm != "") {
                ; Glyph in the upper area, caption beneath (mirrors the digit keys).
                KpText(G, kd.t, kx, ky + 6*s, kw, kh - 30*s, sz*s, VirtualGrid.ColTxt, kd.k != "text")
                KpText(G, nm, kx, ky + kh - 30*s, kw, 24*s, 12*s, VirtualGrid.ColName)
            } else {
                KpText(G, kd.t, kx, ky, kw, kh, sz*s, VirtualGrid.ColTxt, kd.k != "text")
            }
        } else if (kd.k = "icon") {
            isz := Round(40 * s)
            KpIcon(G, A_ScriptDir "\" kd.ic, kx + (kw - isz)//2, ky + (kh - isz)//2, isz, isz)
        }
    }

    ; ---- Alert list panel (to the right of the keypad) ----
    Alerts.RowHits := []
    if (showPanel) {
        KpFill(G, panelX, 0, panelW, kpH, 18*s, VirtualGrid.ColPanel)

        hY      := Round(12*s)
        KpText(G, "Alerts", panelX + 16*s, hY, panelW - 32*s, 26*s, 15*s, VirtualGrid.ColName, true, 0)

        listTop := hY + Round(34*s)
        rowH    := Round(26*s)
        maxRows := Floor((kpH - listTop - 10*s) / rowH)
        rows    := Min(Alerts.List.Length, maxRows)

        Loop rows {
            a  := Alerts.List[A_Index]
            ry := listTop + (A_Index - 1) * rowH
            txtCol := a.unresolved ? VirtualGrid.ColTxt : VirtualGrid.ColName
            ; Unresolved rows get a leading yellow dot.
            if (a.unresolved)
                KpDot(G, panelX + 18*s, ry + rowH/2, 5*s, VirtualGrid.ColAlert)
            label := a.project " [ " a.alerter " ]"
            KpText(G, label, panelX + 32*s, ry, panelW - 44*s, rowH, 13*s, txtCol, false, 0)
            ; Record the row's rect (bitmap-relative) so a click can jump to its desktop.
            Alerts.RowHits.Push({ x1: panelX, y1: ry, x2: panelX + panelW, y2: ry + rowH, num: a.num })
        }
    }

    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", G)
    return pBmp
}

KpRoundedPath(x, y, w, h, r) {
    d := r * 2
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,     "Float", y,     "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y,     "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y+h-d, "Float", d, "Float", d, "Float", 0,   "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,     "Float", y+h-d, "Float", d, "Float", d, "Float", 90,  "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    return path
}

KpFill(G, x, y, w, h, r, argb) {
    path := KpRoundedPath(x, y, w, h, r)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", G, "Ptr", br, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

KpStroke(G, x, y, w, h, r, argb, width) {
    path := KpRoundedPath(x, y, w, h, r)
    DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", width, "Int", 2, "Ptr*", &pen := 0)
    DllCall("gdiplus\GdipDrawPath", "Ptr", G, "Ptr", pen, "Ptr", path)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

; align: 0=left(near), 1=center, 2=right(far). Strings never wrap (NoWrap flag), so
; over-long labels clip to the rect instead of spilling onto a second line.
KpText(G, str, x, y, w, h, size, argb, bold := false, align := 1) {
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "Str", "Segoe UI", "Ptr", 0, "Ptr*", &fam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", size, "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font := 0)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0x4000, "Int", 0, "Ptr*", &fmt := 0) ; 0x4000 = NoWrap
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", align)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    rc := Buffer(16)
    NumPut("Float", x, rc, 0), NumPut("Float", y, rc, 4), NumPut("Float", w, rc, 8), NumPut("Float", h, rc, 12)
    DllCall("gdiplus\GdipDrawString", "Ptr", G, "Str", String(str), "Int", -1, "Ptr", font, "Ptr", rc, "Ptr", fmt, "Ptr", br)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
}

KpIcon(G, path, x, y, w, h) {
    DllCall("gdiplus\GdipCreateBitmapFromFile", "Str", path, "Ptr*", &img := 0)
    if img {
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", G, "Ptr", img, "Int", x, "Int", y, "Int", w, "Int", h)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    }
}

; Filled circle centered at (cx, cy) with radius r — the unresolved-alert marker.
KpDot(G, cx, cy, r, argb) {
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillEllipse", "Ptr", G, "Ptr", br, "Float", cx - r, "Float", cy - r, "Float", 2*r, "Float", 2*r)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
}

; Blit a 32bpp ARGB GDI+ bitmap onto a layered window at (x,y) with per-pixel alpha.
KpBlitLayered(hwnd, pBmp, x, y, w, h) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBmp, "Ptr*", &hbm := 0, "UInt", 0x00000000)
    oldBm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

    ptDst := Buffer(8), NumPut("Int", x, ptDst, 0), NumPut("Int", y, ptDst, 4)
    size  := Buffer(8), NumPut("Int", w, size, 0), NumPut("Int", h, size, 4)
    ptSrc := Buffer(8, 0)
    blend := Buffer(4, 0)
    NumPut("UChar", 0,   blend, 0) ; BlendOp = AC_SRC_OVER
    NumPut("UChar", 0,   blend, 1) ; BlendFlags
    NumPut("UChar", 255, blend, 2) ; SourceConstantAlpha
    NumPut("UChar", 1,   blend, 3) ; AlphaFormat = AC_SRC_ALPHA

    DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", hdcScreen, "Ptr", ptDst, "Ptr", size, "Ptr", hdcMem, "Ptr", ptSrc, "UInt", 0, "Ptr", blend, "UInt", 2) ; ULW_ALPHA

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", oldBm)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
}

; =============================================================================
; ALERTS (desktop-aware notifications)
; -----------------------------------------------------------------------------
; The `alert` skill appends one tab-delimited line per alert to alerts.log:
;     epoch <TAB> {GUID} <TAB> project <TAB> alerter
; An alert is "unresolved" until you visit the desktop it fired on. Visiting a
; desktop stamps a per-desktop watermark (visits.ini): an alert counts as
; unresolved iff it's not on the current desktop AND its epoch is newer than the
; watermark for its desktop. The keypad shows a yellow dot on desktops with
; unresolved alerts and lists recent alerts beside it; clicking a row jumps there.
; =============================================================================

AlertsFile() => A_AppData "\Sygnal HotPad\alerts.log"
VisitsFile() => A_AppData "\Sygnal HotPad\visits.ini"

; Seconds since the Unix epoch (UTC), matching what the skill writes.
NowEpoch() => DateDiff(A_NowUTC, "19700101000000", "Seconds")

; Format a 16-byte COM GUID buffer as "{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}"
; (uppercase, braces) — byte-for-byte identical to PowerShell's Guid.ToString("B").
GuidToStr(buf) {
    s := "{"
    s .= Format("{:08X}", NumGet(buf, 0, "UInt"))   "-"
    s .= Format("{:04X}", NumGet(buf, 4, "UShort"))  "-"
    s .= Format("{:04X}", NumGet(buf, 6, "UShort"))  "-"
    s .= Format("{:02X}", NumGet(buf, 8, "UChar"))
    s .= Format("{:02X}", NumGet(buf, 9, "UChar"))   "-"
    Loop 6
        s .= Format("{:02X}", NumGet(buf, 9 + A_Index, "UChar"))
    return s "}"
}

; The stable GUID of desktop number n (1-based), via the VD library internals.
GuidFromDesktopNum(n) {
    ivd := VD._GetDesktops_Obj().GetAt(n)
    if (!ivd)
        return ""
    buf := Buffer(16, 0)
    DllCall(VD._vtable(ivd, VD.idx_GetId), "Ptr", ivd, "Ptr", buf)
    return GuidToStr(buf)
}

; Map of current "{GUID}" -> desktop number, rebuilt each time (desktops reorder).
BuildGuidNumMap() {
    m := Map()
    Loop VD.getCount()
        m[GuidFromDesktopNum(A_Index)] := A_Index
    return m
}

; --- Visit watermarks (visits.ini: one "{GUID}=epoch" per line) ---
LoadVisits() {
    Alerts.Visits := Map()
    f := VisitsFile()
    if !FileExist(f)
        return
    Loop Read f {
        eq := InStr(A_LoopReadLine, "=")
        if (eq < 2)
            continue
        guid := Trim(SubStr(A_LoopReadLine, 1, eq - 1))
        val  := Trim(SubStr(A_LoopReadLine, eq + 1))
        if (guid != "" && IsInteger(val))
            Alerts.Visits[guid] := Integer(val)
    }
}

SaveVisits() {
    dir := A_AppData "\Sygnal HotPad"
    if !DirExist(dir)
        DirCreate(dir)
    s := ""
    for guid, ep in Alerts.Visits
        s .= guid "=" ep "`n"
    f := VisitsFile()
    try FileDelete(f)
    FileAppend(s, f, "UTF-8")
}

; Visiting desktop `num` resolves its alerts: stamp its watermark to now.
MarkVisited(num) {
    if (!Alerts.LoadedVisits) {
        LoadVisits()
        Alerts.LoadedVisits := true
    }
    guid := GuidFromDesktopNum(num)
    if (guid = "")
        return
    Alerts.Visits[guid] := NowEpoch()
    SaveVisits()
}

; Read alerts.log, classify resolved/unresolved against the visit watermarks and
; the current desktop, and populate Alerts.List (cap 20, unresolved-then-newest)
; plus Alerts.UnresByNum (desktop number -> has-unresolved-alert, for the dots).
LoadAlertsModel(current) {
    if (!Alerts.LoadedVisits) {
        LoadVisits()
        Alerts.LoadedVisits := true
    }
    guidNum := BuildGuidNumMap()
    curGuid := GuidFromDesktopNum(current)

    items := []
    unres := Map()
    f := AlertsFile()
    if FileExist(f) {
        Loop Read f {
            if (Trim(A_LoopReadLine) = "")
                continue
            p := StrSplit(A_LoopReadLine, "`t")
            if (p.Length < 4 || !IsInteger(p[1]))
                continue
            ep    := Integer(p[1])
            guid  := p[2]
            vis   := Alerts.Visits.Has(guid) ? Alerts.Visits[guid] : 0
            isUnr := (guid != curGuid) && (ep > vis)
            num   := guidNum.Has(guid) ? guidNum[guid] : 0
            items.Push({ epoch: ep, guid: guid, project: p[3], alerter: p[4], unresolved: isUnr, num: num })
            if (isUnr && num > 0)
                unres[num] := true
        }
    }

    SortAlerts(items)   ; unresolved first, then newest first

    list := []
    for a in items {
        list.Push(a)
        if (list.Length >= 20)
            break
    }
    Alerts.List := list
    Alerts.UnresByNum := unres
}

; True if alert a should sort before b: unresolved outranks resolved, then newer
; outranks older.
AlertBefore(a, b) {
    if (a.unresolved != b.unresolved)
        return a.unresolved
    return a.epoch > b.epoch
}

; In-place insertion sort (alert counts are small).
SortAlerts(arr) {
    Loop arr.Length - 1 {
        i := A_Index + 1
        key := arr[i]
        j := i - 1
        while (j >= 1 && AlertBefore(key, arr[j])) {
            arr[j + 1] := arr[j]
            j--
        }
        arr[j + 1] := key
    }
}

; =============================================================================
; SETTINGS (persisted per-machine in %APPDATA%\Sygnal HotPad\settings.ini)
; =============================================================================

ConfigFile() => A_AppData "\Sygnal HotPad\settings.ini"

LoadConfig() {
    VirtualGrid.Scale := IniRead(ConfigFile(), "Keypad", "Scale", "1.0") + 0 ; +0 -> number
}

SaveScale(scale) {
    dir := A_AppData "\Sygnal HotPad"
    if !DirExist(dir)
        DirCreate(dir)
    IniWrite(scale, ConfigFile(), "Keypad", "Scale")
    VirtualGrid.Scale := scale
    VirtualGrid.ShownFor := -1 ; force a re-render at the new scale next time the keypad shows
}

; Combined Desktop + Settings + Launchers dialog. Dark, with custom (on-theme)
; tab headers. startTab = "desktop" | "settings" | "launchers".
; Opened from Ctrl+Win+NumpadDot (Desktop tab) and the tray menu. A single Save
; applies the desktop name, the keypad settings, AND the launcher assignments.
ShowHotpadDialog(startTab := "desktop") {
    static gOpen := 0
    if (gOpen && WinExist("ahk_id " gOpen)) {   ; already open -> just surface it
        WinActivate("ahk_id " gOpen)
        return
    }

    n := VD.getCurrentDesktopNum()
    VirtualGrid.Naming := true   ; suppress the HUD while the dialog is up
    HideGrid()

    ; A working copy of the launcher config the Launchers tab edits; committed on Save.
    workItems := Map()
    for id, e in LaunchCfg.Items
        workItems[id] := {action: e.action, path: (e.HasOwnProp("path") ? e.path : ""), args: (e.HasOwnProp("args") ? e.args : ""), profile: (e.HasOwnProp("profile") ? e.profile : "ask"), name: (e.HasOwnProp("name") ? e.name : "")}

    dlg := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Sygnal HotPad")
    dlg.BackColor := "2B2B2B"
    dlg.MarginX := 16, dlg.MarginY := 14

    ; Custom dark tab strip (selected = blue; text stays white for all so we only
    ; have to toggle the background, which Opt()+Redraw handles cleanly).
    dlg.SetFont("s10 Bold", "Segoe UI")
    tabW := 112, tabH := 30
    hD := dlg.AddText("xm ym w" tabW " h" tabH " Center 0x200 cFFFFFF Background3A3A3A", "Desktop")
    hS := dlg.AddText("x+2 yp w" tabW " h" tabH " Center 0x200 cFFFFFF Background3A3A3A", "Settings")
    hL := dlg.AddText("x+2 yp w" tabW " h" tabH " Center 0x200 cFFFFFF Background3A3A3A", "Launchers")
    dlg.SetFont("s10 Norm")

    cy := tabH + 28   ; top of the panel content, just below the tab strip

    ; --- Desktop panel: rename the current desktop ---
    lblD := dlg.AddText("xm y" cy " cD6D6D6", "Name for desktop " n ":")
    edit := dlg.AddEdit("xm y+8 w360 r1 Background3A3A3A cFFFFFF -E0x200")
    edit.Value := DesktopName(n)

    ; --- Settings panel: system-level hotpad settings (panels overlap; toggled by
    ; tab). Add new system settings here. ---
    dlg.SetFont("s10 Bold")
    lblS := dlg.AddText("xm y" cy " cD6D6D6", "Keypad size")
    dlg.SetFont("s10 Norm")
    rS := dlg.AddRadio("xm y+10 cE0E0E0" (VirtualGrid.Scale < 1.25 ? " Checked" : ""), "Small  (100%)")
    rM := dlg.AddRadio("xm y+6 cE0E0E0" (VirtualGrid.Scale >= 1.25 && VirtualGrid.Scale < 1.75 ? " Checked" : ""), "Medium  (150%)")
    rL := dlg.AddRadio("xm y+6 cE0E0E0" (VirtualGrid.Scale >= 1.75 ? " Checked" : ""), "Large  (200%)")

    ; --- Launchers panel: a Key | Action | Target table. Double-click a row (or
    ; Edit…) to assign it an app or Chrome+profile. ---
    lblL := dlg.AddText("xm y" cy " cD6D6D6", "Ctrl+Win + each key launches its assignment. Double-click a row to change it.")
    lv := dlg.AddListView("xm y+8 w360 r9 Background2B2B2B cE0E0E0 -Multi +LV0x10000", ["Key", "Name", "Action", "Target"])  ; LVS_EX_DOUBLEBUFFER

    RefreshLV() {
        lv.Delete()
        for d in LauncherDefs() {
            e := workItems.Has(d.id) ? workItems[d.id] : 0
            nm := (e && e.HasOwnProp("name") && e.name != "") ? e.name : "—"
            if (!e || e.action = "" || e.action = "none") {
                lv.Add(, d.glyph, "—", "—", "—")
                continue
            }
            if (e.action = "chrome") {
                tgt := (e.profile = "ask" || e.profile = "") ? "(ask each time)" : e.profile
                lv.Add(, d.glyph, nm, "Chrome", tgt)
            } else {
                base := ""
                if (e.path != "")
                    SplitPath(e.path, &base)
                lv.Add(, d.glyph, nm, "Application", base = "" ? "—" : base)
            }
        }
        lv.ModifyCol(1, 40), lv.ModifyCol(2, 95), lv.ModifyCol(3, 90), lv.ModifyCol(4, 130)
    }

    EditSelected() {
        row := lv.GetNext()
        if !row
            return
        d := LauncherDefs()[row]
        cur := workItems.Has(d.id) ? workItems[d.id] : {action: "none", path: "", args: "", profile: "ask", name: ""}
        res := EditLauncher(dlg, d.glyph, cur)
        if (res != "") {
            workItems[d.id] := res
            RefreshLV()
            lv.Modify(row, "Select Focus")
        }
    }

    ; --- shared buttons, below the tallest (Launchers) panel ---
    dlg.SetFont("s9")
    save := dlg.AddButton("xm y+16 w95 Default", "Save")
    cancel := dlg.AddButton("x+10 w95", "Cancel")
    dlg.SetFont("s10 Norm")

    desktopCtrls  := [lblD, edit]
    settingsCtrls := [lblS, rS, rM, rL]
    launcherCtrls := [lblL, lv]

    SwitchTab(which) {
        isD := (which = "desktop"), isS := (which = "settings"), isL := (which = "launchers")
        for c in desktopCtrls
            c.Visible := isD
        for c in settingsCtrls
            c.Visible := isS
        for c in launcherCtrls
            c.Visible := isL
        hD.Opt(isD ? "Background1E90FF" : "Background3A3A3A")
        hS.Opt(isS ? "Background1E90FF" : "Background3A3A3A")
        hL.Opt(isL ? "Background1E90FF" : "Background3A3A3A")
        hD.Redraw(), hS.Redraw(), hL.Redraw()
        if (isD) {
            edit.Focus()
            try SendMessage(0xB1, 0, -1, edit)   ; EM_SETSEL -> select all
        }
    }

    Finish(savep) {
        nm := edit.Value, sc := rS.Value ? 1.0 : rM.Value ? 1.5 : 2.0
        gOpen := 0
        dlg.Destroy()
        VirtualGrid.Naming := false   ; HUD rebuilds on next show (ShownFor was reset)
        if (savep) {
            VD.setNameToDesktopNum(nm, n)
            SaveScale(sc)
            SaveLaunchers(workItems)
        }
    }

    hD.OnEvent("Click", (*) => SwitchTab("desktop"))
    hS.OnEvent("Click", (*) => SwitchTab("settings"))
    hL.OnEvent("Click", (*) => SwitchTab("launchers"))
    lv.OnEvent("DoubleClick", (*) => EditSelected())
    save.OnEvent("Click", (*) => Finish(true))
    cancel.OnEvent("Click", (*) => Finish(false))
    dlg.OnEvent("Escape", (*) => Finish(false))
    dlg.OnEvent("Close", (*) => Finish(false))

    RefreshLV()
    dlg.Show("AutoSize Center")   ; sized for all panels (everything visible here)
    SwitchTab(startTab)            ; then reveal just the requested tab
    gOpen := dlg.Hwnd
}

; Modal sub-dialog to assign one operator key. Returns the new item object
; {action, path, args, profile, name}, or "" if cancelled. Fixed layout: the App
; and Chrome controls share the same region (y 134/156) and are toggled by Action.
EditLauncher(parent, glyph, cur) {
    result := ""
    g := Gui("-MinimizeBox -MaximizeBox +Owner" parent.Hwnd, "Assign " glyph " key")
    g.BackColor := "2B2B2B"
    g.MarginX := 16, g.MarginY := 14
    g.SetFont("s10", "Segoe UI")

    g.AddText("xm y14 cD6D6D6", "When you press Ctrl+Win+" glyph ":")
    actDDL := g.AddDropDownList("xm y36 w320 Choose" (cur.action = "app" ? 2 : cur.action = "chrome" ? 3 : 1), ["Do nothing", "Launch an application", "Open Chrome"])

    ; Name shown on the keypad HUD (common to app + chrome).
    nameLbl := g.AddText("xm y74 cD6D6D6", "Name (shown on the keypad):")
    nameEd  := g.AddEdit("xm y96 w320 r1 -Multi -Wrap Background3A3A3A cFFFFFF -E0x200", cur.HasOwnProp("name") ? cur.name : "")

    ; Application controls.
    appLbl  := g.AddText("xm y134 cD6D6D6", "Program:")
    pathEd  := g.AddEdit("xm y156 w320 r1 -Multi -Wrap Background3A3A3A cFFFFFF -E0x200", cur.action = "app" ? cur.path : "")
    browse  := g.AddButton("xm y186 w120", "Browse…")
    argsLbl := g.AddText("xm y222 cD6D6D6", "Arguments (optional):")
    argsEd  := g.AddEdit("xm y244 w320 Background3A3A3A cFFFFFF -E0x200", cur.action = "app" ? cur.args : "")

    ; Chrome controls, sharing the App region's top.
    profList := ["Ask each time"]
    for p in ChromeProfileDirs()
        profList.Push(p)
    chooseIdx := 1
    if (cur.action = "chrome" && cur.profile != "ask" && cur.profile != "") {
        for i, p in profList
            if (p = cur.profile)
                chooseIdx := i
    }
    profLbl := g.AddText("xm y134 cD6D6D6", "Profile:")
    profDDL := g.AddDropDownList("xm y156 w320 Choose" chooseIdx, profList)

    okBtn := g.AddButton("xm y294 w95 Default", "OK")
    cnBtn := g.AddButton("x+10 yp w95", "Cancel")

    UpdateMode(*) {
        m := actDDL.Value   ; 1=none 2=app 3=chrome
        for c in [nameLbl, nameEd]
            c.Visible := (m != 1)
        for c in [appLbl, pathEd, browse, argsLbl, argsEd]
            c.Visible := (m = 2)
        for c in [profLbl, profDDL]
            c.Visible := (m = 3)
    }

    PickFile(*) {
        f := FileSelect(3, , "Choose a program", "Programs (*.exe)")
        if (f != "")
            pathEd.Value := f
    }

    Done(ok) {
        if (ok) {
            m := actDDL.Value
            nm := nameEd.Value
            if (m = 1)
                result := {action: "none", path: "", args: "", profile: "ask", name: ""}
            else if (m = 2)
                result := {action: "app", path: pathEd.Value, args: argsEd.Value, profile: "ask", name: nm}
            else
                result := {action: "chrome", path: "", args: "", profile: (profDDL.Text = "Ask each time" ? "ask" : profDDL.Text), name: nm}
        }
        g.Destroy()
    }

    actDDL.OnEvent("Change", UpdateMode)
    browse.OnEvent("Click", PickFile)
    okBtn.OnEvent("Click", (*) => Done(true))
    cnBtn.OnEvent("Click", (*) => Done(false))
    g.OnEvent("Escape", (*) => Done(false))
    g.OnEvent("Close", (*) => Done(false))

    UpdateMode()
    parent.Opt("+Disabled")
    g.Show("w352 h340 Center")
    WinWaitClose("ahk_id " g.Hwnd)
    parent.Opt("-Disabled")
    WinActivate("ahk_id " parent.Hwnd)
    return result
}
