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
; # = Win
; ! = Alt
; + = Shift

; NAVIGATE TO PREVIOUS DESKTOP WITH WRAP-AROUND
; CTRL+WIN+Left

^#Left:: {
    currentDesktop := VD.getCurrentDesktopNum()
    totalDesktops := VD.getCount()

    ; Loop around to the last desktop if at the first one
    previousDesktop := (currentDesktop = 1) ? totalDesktops : currentDesktop - 1
    VD.goToDesktopNum(previousDesktop)
}

; NAVIGATE TO NEXT DESKTOP WITH WRAP-AROUND
; CTRL+WIN+Right

^#Right:: {
    currentDesktop := VD.getCurrentDesktopNum()
    totalDesktops := VD.getCount()

    ; Loop around to the first desktop if at the last one
    nextDesktop := (currentDesktop = totalDesktops) ? 1 : currentDesktop + 1
    VD.goToDesktopNum(nextDesktop)
}
