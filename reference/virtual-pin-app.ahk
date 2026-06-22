; Hotkeys to pin apps or individual windows to all virtual desktops

;#SETUP START
#SingleInstance force
ListLines 0
SendMode "Input"
SetWorkingDir A_ScriptDir
KeyHistory 0
#WinActivateForce

ProcessSetPriority "H"

SetWinDelay -1
SetControlDelay -1

; Include the virtual desktop helper library
#Include ../lib/VD.ah2

; Hide tray utilities that expose invisible windows
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

return

; CTRL + WIN + Z => pin the active application's exe so all of its windows show on every desktop
^#z::PinActiveApp()

; CTRL + WIN + X => pin only the currently focused window to all desktops
^#x::PinActiveWindow()

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
