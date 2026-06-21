#SingleInstance force
ListLines 0
SendMode "Input"
SetWorkingDir A_ScriptDir
KeyHistory 0
#WinActivateForce
ProcessSetPriority "H"
SetWinDelay -1
SetControlDelay -1

; Remap Windows emoji hotkeys to activate Chrome and open tab search
#.:: {  ; Win + . (period)
    ; Find the topmost Chrome window
    if WinExist("ahk_exe chrome.exe") {
        WinActivate  ; Activate the Chrome window we found
        Sleep 50     ; Brief delay to ensure activation completes
        Send "^+a"   ; Open Chrome tab search (Ctrl+Shift+A)
    }
    return
}

#;:: {  ; Win + ; (semicolon)
    ; Find the topmost Chrome window
    if WinExist("ahk_exe chrome.exe") {
        WinActivate  ; Activate the Chrome window we found
        Sleep 50     ; Brief delay to ensure activation completes
        Send "^+a"   ; Open Chrome tab search (Ctrl+Shift+A)
    }
    return
}
