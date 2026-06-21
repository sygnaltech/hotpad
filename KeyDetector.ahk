#SingleInstance force
#Requires AutoHotkey v2.0

; Universal key detector - will show info for ANY key pressed
; Press your emoji key and watch for the tooltip

; Create an input hook to capture all keyboard input
ih := InputHook("L1 T2")
ih.KeyOpt("{All}", "N")  ; Notify for all keys
ih.OnKeyDown := KeyPressed

; Start the hook
ih.Start()

KeyPressed(hook, vk, sc) {
    keyName := GetKeyName(Format("vk{:x}sc{:x}", vk, sc))
    vkHex := Format("vk{:X}", vk)
    scHex := Format("sc{:X}", sc)

    msg := "Key detected!`n"
    msg .= "Name: " keyName "`n"
    msg .= "VK: " vkHex "`n"
    msg .= "SC: " scHex

    ToolTip msg
    SetTimer () => ToolTip(), -3000

    ; Restart the hook
    hook.Stop()
    hook.Start()
}

; Keep script running
Persistent
