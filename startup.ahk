#SingleInstance force
ListLines 0
SendMode "Input"
SetWorkingDir A_ScriptDir
KeyHistory 0
#WinActivateForce
ProcessSetPriority "H"
SetWinDelay -1
SetControlDelay -1

scripts := [
    "VD-navigate-wraparound.ahk",
    "VD-move-window.ahk",
    "VD-move-window-with-desktop.ahk",
    "VD-pin-app.ahk"
]

for script in scripts {
    LaunchScript(script)
}

return

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
