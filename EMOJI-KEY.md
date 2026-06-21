# Remapping the Microsoft Keyboard Emoji Key

## Problem
The Microsoft Ergonomic Keyboard emoji key (the key with a smiley face between Right Alt and Right Ctrl) **cannot be intercepted by AutoHotkey**. It operates at a hardware/firmware level that bypasses normal key detection.

## Solution (2 Steps)

### Step 1: Disable the Emoji Key via Registry

1. Double-click `DisableEmojiKey.reg` in this folder
2. Click "Yes" to allow registry changes
3. **RESTART YOUR COMPUTER** (required for registry changes to take effect)

After restart, the emoji key will do nothing.

### Step 2: Remap the Key

**Option A: Use PowerToys (Recommended)**
1. Download PowerToys from Microsoft: https://github.com/microsoft/PowerToys/releases
2. Install and open PowerToys
3. Go to Keyboard Manager
4. Click "Remap a key"
5. Map the emoji key to F13 (or another unused function key)
6. Now AutoHotkey can intercept F13

**Option B: Use SharpKeys**
1. Download SharpKeys: https://github.com/randyrants/sharpkeys/releases
2. Install and run it
3. Click "Add"
4. Select the emoji key on the left (should appear as "Special: Emoji")
5. Select F13 on the right
6. Click OK, then "Write to Registry"
7. Restart computer

### Step 3: Update ChromeAppsKey.ahk

Once the emoji key is remapped to F13, edit `ChromeAppsKey.ahk` and replace the hotkey with:

```ahk
F13:: {
    if WinExist("ahk_exe chrome.exe") {
        WinActivate
        Sleep 50
        Send "^+a"
    }
}
```

## Why This Is Complicated

Microsoft designed the emoji key to work at a low level that bypasses standard keyboard input. This prevents AutoHotkey from seeing it. The only solution is:
1. Disable it in registry (removes its hardcoded function)
2. Remap it to a normal key using a remapping tool
3. Then AutoHotkey can intercept the remapped key

## Sources
- [AutoHotkey Community - Reassign Microsoft emoji key](https://www.autohotkey.com/boards/viewtopic.php?t=103581)
- [Microsoft Q&A - How to disable Office/Emoji keys](https://learn.microsoft.com/en-us/answers/questions/357052/how-to-disable-the-office-and-emoticon-keys-on-a-m)
- [PowerToys GitHub Issue #38583](https://github.com/microsoft/PowerToys/issues/38583)
