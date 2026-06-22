; =============================================================================
; VD-combined.ahk
; Consolidated virtual-desktop suite - runs as ONE process / ONE tray icon.
;
; Merged from (originals kept in repo, but no longer launched individually):
;   - VD-navigate-wraparound.ahk
;   - VD-move-window.ahk
;   - VD-numpad-desktops.ahk
;   - VD-pin-app.ahk
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
class VDGrid {
    ; Appearance - tweak here.
    static CellW := 104         ; cell width (px)  - wider to fit names
    static CellH := 72          ; cell height (px)
    static NumH  := 46          ; height of the number area within a cell
    static Gap   := 8           ; gap between cells
    static Pad   := 12          ; window padding
    static ColBg      := "1A1A1A"  ; window background
    static ColCurrent := "1E90FF"  ; current desktop (matches tray icon blue)
    static ColExists  := "3A3A3A"  ; an existing, non-current desktop
    static ColMissing := "222222"  ; a desktop that doesn't exist yet
    static TxtCurrent := "FFFFFF"
    static TxtExists  := "DDDDDD"
    static TxtMissing := "555555"

    ; Runtime state.
    static Hud := 0             ; the Gui object while shown, else 0
    static ShownFor := -1       ; which desktop the shown grid highlights
    static Naming := false      ; true while the rename box is open (suppresses the HUD)
}

; ---- Init (auto-execute section) -------------------------------------------
; Distinct tray icon + tooltip so the single combined process is identifiable.
; A_ScriptDir is the entry script's dir (works whether run directly or #Included
; from startup.ahk, since both live alongside VD-icon.ico).
TraySetIcon A_ScriptDir "\VD-icon.ico"
A_IconTip := "Virtual Desktop Suite"

VD.createUntil(3) ; Create until we have at least 3 virtual desktops

; The Numpad1..9 hotkeys are registered at runtime, so this loop MUST run in the
; auto-execute section (before the first `return`/hotkey label) or they won't bind.
Loop 9 {
    n := A_Index
    Hotkey "^#Numpad" n, NavigateAbsoluteClosure(n)    ; Ctrl+Win+N       -> switch to desktop N
    Hotkey "^!#Numpad" n, MoveAbsoluteFollowClosure(n) ; Ctrl+Alt+Win+N   -> move window to N + follow
    Hotkey "!#Numpad" n, MoveAbsoluteStayClosure(n)    ; Alt+Win+N        -> move window to N, stay
}

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

; --- Rename current desktop (Ctrl+Win + decimal point) ---
; NumpadDot = NumLock on, NumpadDel = NumLock off.
^#NumpadDot:: RenameCurrentDesktop()
^#NumpadDel:: RenameCurrentDesktop()

; =============================================================================
; CLOSURE FACTORIES (for the runtime-registered Numpad hotkeys)
; Each call creates a fresh scope so the captured desktop number is correct
; (avoids the classic "all hotkeys see the final loop value" bug).
; =============================================================================
NavigateAbsoluteClosure(n)   => (*) => NavigateAbsolute(n)
MoveAbsoluteFollowClosure(n) => (*) => MoveActiveAbsolute(n, true)
MoveAbsoluteStayClosure(n)   => (*) => MoveActiveAbsolute(n, false)

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
    if VDGrid.Naming
        return
    if ChordHeld()
        ShowOrUpdateGrid()
    else
        HideGrid()
}

RenameCurrentDesktop() {
    n := VD.getCurrentDesktopNum()

    VDGrid.Naming := true
    HideGrid() ; get the HUD out of the way of the dialog

    ib := InputBox("Enter a name for desktop " n ":", "Rename desktop " n, "w300 h130", DesktopName(n))

    VDGrid.Naming := false
    if (ib.Result = "OK")
        VD.setNameToDesktopNum(ib.Value, n)
    ; Next time the grid shows it rebuilds from scratch (HideGrid reset ShownFor),
    ; so the new name appears automatically.
}

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
    if (VDGrid.Hud && VDGrid.ShownFor = current)
        return

    if VDGrid.Hud
        VDGrid.Hud.Destroy()

    count := VD.getCount()

    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000") ; E0x08000000 = WS_EX_NOACTIVATE
    g.BackColor := VDGrid.ColBg

    ; Rows top->bottom hold 7-9, 4-6, 1-3 so 1 lands bottom-left, 9 top-right.
    Loop 3 {
        r := A_Index - 1
        Loop 3 {
            c := A_Index - 1
            n := (2 - r) * 3 + (c + 1)

            if (n = current) {
                bg := VDGrid.ColCurrent
                fg := VDGrid.TxtCurrent
            } else if (n <= count) {
                bg := VDGrid.ColExists
                fg := VDGrid.TxtExists
            } else {
                bg := VDGrid.ColMissing
                fg := VDGrid.TxtMissing
            }

            x := VDGrid.Pad + c * (VDGrid.CellW + VDGrid.Gap)
            y := VDGrid.Pad + r * (VDGrid.CellH + VDGrid.Gap)

            ; Number (top portion of the cell).
            g.SetFont("s20 Bold", "Segoe UI")
            g.Add("Text", Format("x{} y{} w{} h{} Center +0x200 Background{} c{}", x, y, VDGrid.CellW, VDGrid.NumH, bg, fg), n)

            ; Name (bottom strip). Only existing desktops; ellipsis if too long.
            name := (n <= count) ? DesktopName(n) : ""
            g.SetFont("s8 Norm", "Segoe UI")
            g.Add("Text", Format("x{} y{} w{} h{} Center +0x4280 Background{} c{}", x, y + VDGrid.NumH, VDGrid.CellW, VDGrid.CellH - VDGrid.NumH, bg, fg), name)
        }
    }

    w := VDGrid.Pad * 2 + 3 * VDGrid.CellW + 2 * VDGrid.Gap
    h := VDGrid.Pad * 2 + 3 * VDGrid.CellH + 2 * VDGrid.Gap

    ; Center on the primary monitor.
    MonitorGet(MonitorGetPrimary(), &mLeft, &mTop, &mRight, &mBottom)
    px := mLeft + ((mRight - mLeft) - w) // 2
    py := mTop + ((mBottom - mTop) - h) // 2
    g.Show(Format("NoActivate x{} y{} w{} h{}", px, py, w, h))

    VDGrid.Hud := g
    VDGrid.ShownFor := current
}

HideGrid() {
    if !VDGrid.Hud
        return
    VDGrid.Hud.Destroy()
    VDGrid.Hud := 0
    VDGrid.ShownFor := -1
}
