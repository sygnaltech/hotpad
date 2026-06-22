; =============================================================================
; virtual-combined.ahk
; Consolidated virtual-desktop suite - runs as ONE process / ONE tray icon.
;
; Merged from (originals kept in repo, but no longer launched individually):
;   - virtual-navigate-wraparound.ahk
;   - virtual-move-window.ahk
;   - virtual-numpad-desktops.ahk
;   - virtual-pin-app.ahk
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
;   Preview grid (hold):      Ctrl+Win            (numpad-layout HUD of desktops 1-9)
;   Rename current desktop:   Ctrl+Win+NumpadDot  (uses native Win11 names)
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
#Include lib/VD.ah2

; You should WinHide invisible programs that have a window.
try {
    WinHide "Malwarebytes Tray Application"
} catch {
}
;#SETUP END

; ---- Preview-grid config + state --------------------------------------------
; Held in a class so it's reliably accessible from every function. Defined before
; the auto-execute body so its static init isn't flagged as unreachable.
class VirtualGrid {
    ; Keypad geometry (px) - tweak here.
    static Pad  := 18           ; outer padding
    static Cell := 80           ; key size
    static Gap  := 12           ; gap between keys

    ; Colors (ARGB 0xAARRGGBB).
    static ColBody    := 0xFF3A3A3A  ; body + key fill
    static ColStroke  := 0xFF808080  ; key border
    static ColCur     := 0xFF1E90FF  ; current desktop key fill (tray-icon blue)
    static ColCurStrk := 0xFF5CB0FF  ; current desktop key border
    static ColTxt     := 0xFFD6D6D6  ; key glyph / number
    static ColCurTxt  := 0xFFFFFFFF
    static ColName    := 0xFF9AA0A6  ; desktop name
    static ColCurName := 0xFFEAF4FF

    ; Persisted settings (loaded from the config file at startup).
    static Scale := 1.0         ; keypad scale: 1.0 / 1.5 / 2.0 = Small / Medium / Large

    ; Runtime state.
    static Hud := 0             ; the layered Gui while created (kept hidden when not shown)
    static ShownFor := -1       ; which desktop the shown keypad highlights
    static Naming := false      ; true while the rename box is open (suppresses the HUD)
    static GdipToken := 0       ; GDI+ token (started once at init)
}

; Desktop back-stack ("browser back" for virtual desktops). The poll in CheckChord
; records each desktop you leave; Ctrl+Win+Backspace walks back through it.
class VirtualBack {
    static Stack := []          ; desktops you've left, oldest first, newest last
    static Last := 0            ; last-seen current desktop (0 = uninitialized)
    static GoingBack := false   ; true while a back-nav is in flight (don't re-record it)
    static Max := 10            ; how many steps of history to keep
}

; ---- Init (auto-execute section) -------------------------------------------
; Distinct tray icon + tooltip so the single combined process is identifiable.
; A_ScriptDir is the entry script's dir (works whether run directly or #Included
; from startup.ahk, since both live alongside virtual-icon.ico).
TraySetIcon A_ScriptDir "\virtual-icon.ico"
A_IconTip := "Sygnal HotPad"

VD.createUntil(3) ; Create until we have at least 3 virtual desktops

; Start GDI+ once for the preview-keypad renderer.
DllCall("LoadLibrary", "Str", "gdiplus")
gdipSi := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
NumPut("UInt", 1, gdipSi, 0)
DllCall("gdiplus\GdiplusStartup", "Ptr*", &gdipTok := 0, "Ptr", gdipSi, "Ptr", 0)
VirtualGrid.GdipToken := gdipTok

; Load persisted settings, and add a "Settings" entry to the tray right-click menu.
LoadConfig()
A_TrayMenu.Insert("1&", "Settings", ShowSettings)
A_TrayMenu.Insert("2&")

; The Numpad hotkeys are registered at runtime, so this loop MUST run in the
; auto-execute section (before the first `return`/hotkey label) or they won't bind.
; Numpad1..9 -> desktops 1..9; Numpad0 -> desktop 10.
Loop 10 {
    n := A_Index = 10 ? 0 : A_Index   ; the key digit (0 for the 10th)
    d := A_Index                      ; the desktop number (1..10)
    Hotkey "^#Numpad" n, NavigateAbsoluteClosure(d)    ; Ctrl+Win+N       -> switch to desktop d
    Hotkey "^!#Numpad" n, MoveAbsoluteFollowClosure(d) ; Ctrl+Alt+Win+N   -> move window to d + follow
    Hotkey "!#Numpad" n, MoveAbsoluteStayClosure(d)    ; Alt+Win+N        -> move window to d, stay
}

; Poll for the Ctrl+Win chord that shows the preview grid (robust, and never
; interferes with the modifier-based hotkeys above).
SetTimer CheckChord, 75

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

; --- Rename current desktop (Ctrl+Win + decimal point) ---
; NumpadDot = NumLock on, NumpadDel = NumLock off.
^#NumpadDot:: RenameCurrentDesktop()
^#NumpadDel:: RenameCurrentDesktop()

; --- Go back to the previous desktop (Ctrl+Win + Backspace) ---
; No `~`, so the keypress is consumed (suppresses the default Windows action).
; If your numpad's BS key sends a different code, run legacy/key-detector.ahk to
; find it and change the key name below.
^#Backspace:: GoBackDesktop()

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

; Record desktop changes into the back-stack. Runs from CheckChord every 75ms, so
; it catches switches made any way (our hotkeys, native gestures, Task View, etc.).
TrackDesktopHistory() {
    cur := VD.getCurrentDesktopNum()
    if (cur = VirtualBack.Last)
        return
    if (VirtualBack.GoingBack) {
        VirtualBack.GoingBack := false        ; this change was the back-nav itself; don't record
    } else if (VirtualBack.Last != 0) {
        VirtualBack.Stack.Push(VirtualBack.Last)
        while (VirtualBack.Stack.Length > VirtualBack.Max)
            VirtualBack.Stack.RemoveAt(1)     ; drop the oldest beyond the cap
    }
    VirtualBack.Last := cur
}

; "Browser back" for desktops: return to the most recent one you came from.
GoBackDesktop() {
    if (VirtualBack.Stack.Length < 1)
        return
    target := VirtualBack.Stack.Pop()
    VirtualBack.GoingBack := true
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

; =============================================================================
; PREVIEW GRID (hold Ctrl+Win) + DESKTOP RENAME
; =============================================================================

ChordHeld() {
    return GetKeyState("Control", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
}

CheckChord() {
    TrackDesktopHistory()
    if VirtualGrid.Naming
        return
    if ChordHeld()
        ShowOrUpdateGrid()
    else
        HideGrid()
}

RenameCurrentDesktop() {
    n := VD.getCurrentDesktopNum()
    VirtualGrid.Naming := true
    HideGrid() ; get the HUD out of the way of the dialog
    ShowRenameDialog(n, DesktopName(n))
}

; Dark, keypad-styled rename dialog (replaces the default InputBox).
ShowRenameDialog(n, currentName) {
    dlg := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Rename desktop " n)
    dlg.BackColor := "2B2B2B"
    dlg.MarginX := 18, dlg.MarginY := 16
    dlg.SetFont("s10", "Segoe UI")
    dlg.AddText("cD6D6D6", "Name for desktop " n ":")
    edit := dlg.AddEdit("xm y+8 w300 r1 Background3A3A3A cFFFFFF -E0x200")
    edit.Value := currentName
    dlg.SetFont("s9")
    save := dlg.AddButton("xm y+16 w95 Default", "Save")
    cancel := dlg.AddButton("x+10 w95", "Cancel")
    save.OnEvent("Click", (*) => RenameFinish(dlg, edit.Value, n, false))
    cancel.OnEvent("Click", (*) => RenameFinish(dlg, "", n, true))
    dlg.OnEvent("Escape", (*) => RenameFinish(dlg, "", n, true))
    dlg.OnEvent("Close", (*) => RenameFinish(dlg, "", n, true))
    dlg.Show("AutoSize Center")
    edit.Focus()
    try SendMessage(0xB1, 0, -1, edit) ; EM_SETSEL -> select all
}

RenameFinish(dlg, value, n, cancelled) {
    dlg.Destroy()
    VirtualGrid.Naming := false
    ; Next time the keypad shows it rebuilds (HideGrid reset ShownFor), so a new name appears.
    if (!cancelled)
        VD.setNameToDesktopNum(value, n)
}

; The desktop's custom name, or "" if it has none (so we don't print a redundant
; "Desktop N" under the number).
DesktopName(n) {
    name := VD.getNameFromDesktopNum(n)
    try {
        if (name = VD._getLocalizedWord_Desktop() " " n)
            return ""
    }
    return name
}

ShowOrUpdateGrid() {
    current := VD.getCurrentDesktopNum()

    ; Already showing and highlight is current -> nothing to do.
    if (VirtualGrid.Hud && VirtualGrid.ShownFor = current)
        return

    s := VirtualGrid.Scale
    pad := Round(VirtualGrid.Pad * s), cell := Round(VirtualGrid.Cell * s), gap := Round(VirtualGrid.Gap * s)
    kpW := pad*2 + 4*cell + 3*gap
    kpH := pad*2 + 5*cell + 4*gap

    pBmp := RenderKeypad(current, pad, cell, gap, s, kpW, kpH)

    ; Create the layered, no-activate, always-on-top window once; reuse it after.
    if !VirtualGrid.Hud {
        g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x80000 +E0x08000000") ; 0x80000=WS_EX_LAYERED, 0x08000000=WS_EX_NOACTIVATE
        g.Show("NoActivate Hide")
        VirtualGrid.Hud := g
    }

    MonitorGet(MonitorGetPrimary(), &mLeft, &mTop, &mRight, &mBottom)
    px := mLeft + ((mRight - mLeft) - kpW) // 2
    py := mTop + ((mBottom - mTop) - kpH) // 2

    KpBlitLayered(VirtualGrid.Hud.Hwnd, pBmp, px, py, kpW, kpH)
    DllCall("ShowWindow", "Ptr", VirtualGrid.Hud.Hwnd, "Int", 8) ; SW_SHOWNA = show without activating
    DllCall("gdiplus\GdipDisposeImage", "Ptr", pBmp)

    VirtualGrid.ShownFor := current
}

HideGrid() {
    if !VirtualGrid.Hud
        return
    DllCall("ShowWindow", "Ptr", VirtualGrid.Hud.Hwnd, "Int", 0) ; SW_HIDE
    VirtualGrid.ShownFor := -1
}

; ---- Keypad rendering (GDI+) ------------------------------------------------
; Numpad layout. k=kind: digit|glyph|text|icon. d=desktop (digit). lbl overrides
; the drawn label (the 0 key shows "0" but is desktop 10). c/r=col/row, cs/rs=spans.
KpLayout() {
    return [
        {k:"glyph", t:"=",        c:0, r:0},
        {k:"glyph", t:"/",        c:1, r:0},
        {k:"glyph", t:"*",        c:2, r:0},
        {k:"icon",  ic:"assets\keys\bs.png", c:3, r:0},
        {k:"digit", d:7,          c:0, r:1},
        {k:"digit", d:8,          c:1, r:1},
        {k:"digit", d:9,          c:2, r:1},
        {k:"glyph", t:"−", sz:34,  c:3, r:1},
        {k:"digit", d:4,          c:0, r:2},
        {k:"digit", d:5,          c:1, r:2},
        {k:"digit", d:6,          c:2, r:2},
        {k:"glyph", t:"+", sz:34,  c:3, r:2},
        {k:"digit", d:1,          c:0, r:3},
        {k:"digit", d:2,          c:1, r:3},
        {k:"digit", d:3,          c:2, r:3},
        {k:"text",  t:"Enter", sz:20, c:3, r:3, rs:2},
        {k:"digit", d:10, lbl:"0", c:0, r:4, cs:2},
        {k:"glyph", t:".", sz:34,  c:2, r:4},
    ]
}

RenderKeypad(current, pad, cell, gap, s, kpW, kpH) {
    count := VD.getCount()

    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", kpW, "Int", kpH, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBmp := 0)
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBmp, "Ptr*", &G := 0)
    DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", G, "Int", 4)
    DllCall("gdiplus\GdipSetTextRenderingHint", "Ptr", G, "Int", 4)
    DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", G, "Int", 7)

    KpFill(G, 0, 0, kpW, kpH, 22*s, VirtualGrid.ColBody)

    for kd in KpLayout() {
        cs := kd.HasOwnProp("cs") ? kd.cs : 1
        rs := kd.HasOwnProp("rs") ? kd.rs : 1
        kx := pad + kd.c * (cell + gap)
        ky := pad + kd.r * (cell + gap)
        kw := cell + (cs - 1) * (cell + gap)
        kh := cell + (rs - 1) * (cell + gap)

        isCur := (kd.k = "digit" && kd.d = current)
        KpFill(G, kx, ky, kw, kh, 10*s, isCur ? VirtualGrid.ColCur : VirtualGrid.ColBody)
        KpStroke(G, kx, ky, kw, kh, 10*s, isCur ? VirtualGrid.ColCurStrk : VirtualGrid.ColStroke, 1.5*s)

        if (kd.k = "digit") {
            nm := (kd.d <= count) ? DesktopName(kd.d) : ""
            txtCol := isCur ? VirtualGrid.ColCurTxt : VirtualGrid.ColTxt
            lbl := kd.HasOwnProp("lbl") ? kd.lbl : kd.d
            ; Number always sits in the upper area, name slot reserved below.
            KpText(G, lbl, kx, ky + 6*s, kw, kh - 30*s, 30*s, txtCol, true)
            if (nm != "")
                KpText(G, nm, kx, ky + kh - 30*s, kw, 24*s, 12*s, isCur ? VirtualGrid.ColCurName : VirtualGrid.ColName)
        } else if (kd.k = "glyph" || kd.k = "text") {
            sz := kd.HasOwnProp("sz") ? kd.sz : 30
            KpText(G, kd.t, kx, ky, kw, kh, sz*s, VirtualGrid.ColTxt, kd.k != "text")
        } else if (kd.k = "icon") {
            isz := Round(40 * s)
            KpIcon(G, A_ScriptDir "\" kd.ic, kx + (kw - isz)//2, ky + (kh - isz)//2, isz, isz)
        }
    }

    DllCall("gdiplus\GdipDeleteGraphics", "Ptr", G)
    return pBmp
}

KpRoundedPath(x, y, w, h, r) {
    d := r * 2
    DllCall("gdiplus\GdipCreatePath", "Int", 0, "Ptr*", &path := 0)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,     "Float", y,     "Float", d, "Float", d, "Float", 180, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y,     "Float", d, "Float", d, "Float", 270, "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x+w-d, "Float", y+h-d, "Float", d, "Float", d, "Float", 0,   "Float", 90)
    DllCall("gdiplus\GdipAddPathArc", "Ptr", path, "Float", x,     "Float", y+h-d, "Float", d, "Float", d, "Float", 90,  "Float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "Ptr", path)
    return path
}

KpFill(G, x, y, w, h, r, argb) {
    path := KpRoundedPath(x, y, w, h, r)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    DllCall("gdiplus\GdipFillPath", "Ptr", G, "Ptr", br, "Ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

KpStroke(G, x, y, w, h, r, argb, width) {
    path := KpRoundedPath(x, y, w, h, r)
    DllCall("gdiplus\GdipCreatePen1", "UInt", argb, "Float", width, "Int", 2, "Ptr*", &pen := 0)
    DllCall("gdiplus\GdipDrawPath", "Ptr", G, "Ptr", pen, "Ptr", path)
    DllCall("gdiplus\GdipDeletePen", "Ptr", pen)
    DllCall("gdiplus\GdipDeletePath", "Ptr", path)
}

KpText(G, str, x, y, w, h, size, argb, bold := false) {
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "Str", "Segoe UI", "Ptr", 0, "Ptr*", &fam := 0)
    DllCall("gdiplus\GdipCreateFont", "Ptr", fam, "Float", size, "Int", bold ? 1 : 0, "Int", 2, "Ptr*", &font := 0)
    DllCall("gdiplus\GdipCreateStringFormat", "Int", 0, "Int", 0, "Ptr*", &fmt := 0)
    DllCall("gdiplus\GdipSetStringFormatAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipSetStringFormatLineAlign", "Ptr", fmt, "Int", 1)
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", argb, "Ptr*", &br := 0)
    rc := Buffer(16)
    NumPut("Float", x, rc, 0), NumPut("Float", y, rc, 4), NumPut("Float", w, rc, 8), NumPut("Float", h, rc, 12)
    DllCall("gdiplus\GdipDrawString", "Ptr", G, "Str", String(str), "Int", -1, "Ptr", font, "Ptr", rc, "Ptr", fmt, "Ptr", br)
    DllCall("gdiplus\GdipDeleteBrush", "Ptr", br)
    DllCall("gdiplus\GdipDeleteStringFormat", "Ptr", fmt)
    DllCall("gdiplus\GdipDeleteFont", "Ptr", font)
    DllCall("gdiplus\GdipDeleteFontFamily", "Ptr", fam)
}

KpIcon(G, path, x, y, w, h) {
    DllCall("gdiplus\GdipCreateBitmapFromFile", "Str", path, "Ptr*", &img := 0)
    if img {
        DllCall("gdiplus\GdipDrawImageRectI", "Ptr", G, "Ptr", img, "Int", x, "Int", y, "Int", w, "Int", h)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", img)
    }
}

; Blit a 32bpp ARGB GDI+ bitmap onto a layered window at (x,y) with per-pixel alpha.
KpBlitLayered(hwnd, pBmp, x, y, w, h) {
    hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
    hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBmp, "Ptr*", &hbm := 0, "UInt", 0x00000000)
    oldBm := DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm, "Ptr")

    ptDst := Buffer(8), NumPut("Int", x, ptDst, 0), NumPut("Int", y, ptDst, 4)
    size  := Buffer(8), NumPut("Int", w, size, 0), NumPut("Int", h, size, 4)
    ptSrc := Buffer(8, 0)
    blend := Buffer(4, 0)
    NumPut("UChar", 0,   blend, 0) ; BlendOp = AC_SRC_OVER
    NumPut("UChar", 0,   blend, 1) ; BlendFlags
    NumPut("UChar", 255, blend, 2) ; SourceConstantAlpha
    NumPut("UChar", 1,   blend, 3) ; AlphaFormat = AC_SRC_ALPHA

    DllCall("UpdateLayeredWindow", "Ptr", hwnd, "Ptr", hdcScreen, "Ptr", ptDst, "Ptr", size, "Ptr", hdcMem, "Ptr", ptSrc, "UInt", 0, "Ptr", blend, "UInt", 2) ; ULW_ALPHA

    DllCall("SelectObject", "Ptr", hdcMem, "Ptr", oldBm)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", hdcMem)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
}

; =============================================================================
; SETTINGS (persisted per-machine in %APPDATA%\Sygnal HotPad\settings.ini)
; =============================================================================

ConfigFile() => A_AppData "\Sygnal HotPad\settings.ini"

LoadConfig() {
    VirtualGrid.Scale := IniRead(ConfigFile(), "Keypad", "Scale", "1.0") + 0 ; +0 -> number
}

SaveScale(scale) {
    dir := A_AppData "\Sygnal HotPad"
    if !DirExist(dir)
        DirCreate(dir)
    IniWrite(scale, ConfigFile(), "Keypad", "Scale")
    VirtualGrid.Scale := scale
    VirtualGrid.ShownFor := -1 ; force a re-render at the new scale next time the keypad shows
}

; Tray > Settings window. Dark, matches the keypad/rename styling.
ShowSettings(*) {
    sg := Gui("-MinimizeBox -MaximizeBox +AlwaysOnTop", "Sygnal HotPad - Settings")
    sg.BackColor := "2B2B2B"
    sg.MarginX := 18, sg.MarginY := 16
    sg.SetFont("s10 Bold", "Segoe UI")
    sg.AddText("cD6D6D6", "Keypad size")
    sg.SetFont("s10 Norm", "Segoe UI")
    rS := sg.AddRadio("xm y+10 cE0E0E0" (VirtualGrid.Scale < 1.25 ? " Checked" : ""), "Small  (100%)")
    rM := sg.AddRadio("xm y+6 cE0E0E0" (VirtualGrid.Scale >= 1.25 && VirtualGrid.Scale < 1.75 ? " Checked" : ""), "Medium  (150%)")
    rL := sg.AddRadio("xm y+6 cE0E0E0" (VirtualGrid.Scale >= 1.75 ? " Checked" : ""), "Large  (200%)")
    sg.SetFont("s9")
    save := sg.AddButton("xm y+18 w95 Default", "Save")
    cancel := sg.AddButton("x+10 w95", "Cancel")
    save.OnEvent("Click", (*) => (SaveScale(rS.Value ? 1.0 : rM.Value ? 1.5 : 2.0), sg.Destroy()))
    cancel.OnEvent("Click", (*) => sg.Destroy())
    sg.OnEvent("Escape", (*) => sg.Destroy())
    sg.Show("AutoSize Center")
}
