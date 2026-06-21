; Direct (absolute) virtual-desktop access via the numeric keypad.
; Mirrors the relative-arrow scheme in VD-navigate-wraparound.ahk / VD-move-window.ahk,
; but jumps straight to a numbered desktop (1-9) instead of stepping left/right.
;
; NOTE: NumLock must be ON (these bind the digit keys Numpad1..Numpad9).

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

; Include the library
#Include ../VD.ahk/VD.ah2

; You should WinHide invisible programs that have a window.
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

VD.createUntil(3) ; Create until we have at least 3 virtual desktops

; ^ = Ctrl   ! = Alt   # = Win
; Register Numpad1..Numpad9:
;   Ctrl+Win+N      -> switch to desktop N
;   Ctrl+Alt+Win+N  -> move active window to desktop N and follow
;   Alt+Win+N       -> move active window to desktop N, stay put
Loop 9 {
    n := A_Index
    Hotkey "^#Numpad" n, NavigateClosure(n)
    Hotkey "^!#Numpad" n, MoveFollowClosure(n)
    Hotkey "!#Numpad" n, MoveStayClosure(n)
}

return

; --- Closure factories -------------------------------------------------------
; Each call creates a fresh scope so the captured desktop number is correct
; (avoids the classic "all hotkeys see the final loop value" bug).
NavigateClosure(n)   => (*) => NavigateToDesktop(n)
MoveFollowClosure(n) => (*) => MoveActiveWindowToDesktop(n, true)
MoveStayClosure(n)   => (*) => MoveActiveWindowToDesktop(n, false)

; --- Core --------------------------------------------------------------------
NavigateToDesktop(target) {
    VD.createUntil(target) ; ensure the target desktop exists
    VD.goToDesktopNum(target)
}

; follow:  true  = switch to the target desktop and reactivate the window
;          false = move the window but stay on the current desktop
MoveActiveWindowToDesktop(target, follow) {
    activeWindow := WinExist("A")
    if (!activeWindow) ; nothing focused (e.g. desktop itself) - bail
        return

    VD.createUntil(target) ; ensure the target desktop exists

    ; Move the window first, while everything is still stable on this desktop.
    VD.MoveWindowToDesktopNum("ahk_id " activeWindow, target)

    if (follow) {
        VD.goToDesktopNum(target)
        WaitForDesktop(target) ; the switch is async - wait for it to actually land
        try WinActivate("ahk_id " activeWindow) ; best-effort: a miss is harmless
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
