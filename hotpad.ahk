#SingleInstance force
ListLines 0
SendMode "Input"
SetWorkingDir A_ScriptDir
KeyHistory 0
#WinActivateForce
ProcessSetPriority "H"
SetWinDelay -1
SetControlDelay -1

; Standalone scripts to launch as separate processes (each gets its own tray
; icon). The virtual-desktop suite is NOT here - it's #Included below so it runs
; in THIS process (one tray icon). Add future standalone scripts to this list.
scripts := [
]

for script in scripts {
    LaunchScript(script)
}

; Load the consolidated virtual-desktop suite in-process (single tray icon).
; Must be included here, inside the auto-execute section (before any `return`),
; so its runtime-registered Numpad hotkeys actually bind.
#Include virtual-combined.ahk

LaunchScript(scriptName) {
    scriptPath := A_ScriptDir "\" scriptName

    if !FileExist(scriptPath) {
        OutputDebug Format("startup.ahk: missing {1}", scriptPath)
        return
    }

    if IsScriptRunning(scriptName) {
        OutputDebug Format("startup.ahk: already running {1}", scriptName)
        return
    }

    try {
        Run scriptPath
        OutputDebug Format("startup.ahk: launched {1}", scriptName)
    } catch as err {
        OutputDebug Format("startup.ahk: failed to launch {1} ({2})", scriptName, err.Message)
    }
}

IsScriptRunning(scriptName) {
    DetectHiddenWindows true
    try {
        winList := WinGetList("ahk_class AutoHotkey")
        for hwnd in winList {
            title := WinGetTitle("ahk_id " hwnd)
            if InStr(title, scriptName)
                return true
        }
        return false
    } finally {
        DetectHiddenWindows false
    }
}
