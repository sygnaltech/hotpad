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
#Include ../VD.ahk/VD.ah2

; You should WinHide invisible programs that have a window.
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

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
