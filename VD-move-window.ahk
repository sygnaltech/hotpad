;FROM https://superuser.com/questions/1685845/moving-current-window-to-another-desktop-in-windows-11-using-shortcut-keys

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
#Include lib/VD.ah2
; VD.init() ; COMMENT OUT `static dummyStatic1 := VD.init()` if you don't want to init at start of script

; You should WinHide invisible programs that have a window.
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

VD.createUntil(3) ; Create until we have at least 3 virtual desktops

return

; ^ = Ctrl
; ! = Alt
; # = Win
; + = Shift

; --- Hotkeys -----------------------------------------------------------------
; Move + follow:  Ctrl+Alt+Win+Arrow  and  Ctrl+Win+Shift+Arrow (alias)
; Move + stay:    Alt+Win+Arrow

^!#Right:: MoveActiveWindowToAdjacentDesktop(1, true)
^!#Left::  MoveActiveWindowToAdjacentDesktop(-1, true)

^#+Right:: MoveActiveWindowToAdjacentDesktop(1, true)
^#+Left::  MoveActiveWindowToAdjacentDesktop(-1, true)

!#Right::  MoveActiveWindowToAdjacentDesktop(1, false)
!#Left::   MoveActiveWindowToAdjacentDesktop(-1, false)

; --- Core --------------------------------------------------------------------
; direction:  1 = next desktop, -1 = previous desktop (both wrap around)
; follow:     true  = switch to the target desktop and reactivate the window
;             false = move the window but stay on the current desktop
MoveActiveWindowToAdjacentDesktop(direction, follow) {
    activeWindow := WinExist("A")
    if (!activeWindow) ; nothing focused (e.g. desktop itself) - bail
        return

    currentDesktop := VD.getCurrentDesktopNum()
    totalDesktops := VD.getCount()

    if (direction > 0)
        targetDesktop := (currentDesktop = totalDesktops) ? 1 : currentDesktop + 1
    else
        targetDesktop := (currentDesktop = 1) ? totalDesktops : currentDesktop - 1

    ; Move the window first, while everything is still stable on this desktop.
    VD.MoveWindowToDesktopNum("ahk_id " activeWindow, targetDesktop)

    if (follow) {
        VD.goToDesktopNum(targetDesktop)
        WaitForDesktop(targetDesktop) ; the switch is async - wait for it to actually land
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
