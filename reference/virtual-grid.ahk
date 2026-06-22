; =============================================================================
; virtual-grid.ahk
; A numpad-layout 3x3 HUD of virtual desktops 1-9, shown while Ctrl+Win is held.
; Highlights the current desktop and shows each desktop's (native Windows) name.
; Navigation itself stays on the existing Ctrl+Win+Numpad hotkeys.
;
;   Layout (numpad style):   7 8 9
;                            4 5 6
;                            1 2 3
;
;   Ctrl+Win            -> show the preview while held
;   Ctrl+Win+NumpadDot  -> rename the current desktop (uses native Win11 names,
;                          which persist and also appear in Task View)
;
; Standalone for now (run it alongside the rest); can be folded into virtual-combined later.
; =============================================================================

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

#Include ../lib/VD.ah2
;#SETUP END

; ---- Config + state ---------------------------------------------------------
; Held in a class so it's reliably accessible from every function (avoids the
; v2 "local variable not assigned / global declaration required" pitfall).
; Defined before the auto-execute body so its static init isn't flagged as
; unreachable (which a class after `return` would be).
class VDGrid {
    ; Appearance - tweak here.
    static CellW := 104         ; cell width (px)  - wider to fit names
    static CellH := 72          ; cell height (px)
    static NumH  := 46          ; height of the number area within a cell
    static Gap   := 8           ; gap between cells
    static Pad   := 12          ; window padding
    static ColBg      := "1A1A1A"  ; window background
    static ColCurrent := "1E90FF"  ; current desktop (matches tray icon blue)
    static ColExists  := "3A3A3A"  ; an existing, non-current desktop
    static ColMissing := "222222"  ; a desktop that doesn't exist yet
    static TxtCurrent := "FFFFFF"
    static TxtExists  := "DDDDDD"
    static TxtMissing := "555555"

    ; Runtime state.
    static Hud := 0             ; the Gui object while shown, else 0
    static ShownFor := -1       ; which desktop the shown grid highlights
    static Naming := false      ; true while the rename box is open (suppresses the HUD)
}

VD.createUntil(3)

; Poll for the Ctrl+Win chord. A lightweight always-on timer is far more robust
; than hooking the modifier keys, and never interferes with other hotkeys.
SetTimer CheckChord, 75

return

; ---- Rename hotkey ----------------------------------------------------------
; Ctrl+Win + decimal point. NumpadDot = NumLock on, NumpadDel = NumLock off.
^#NumpadDot:: RenameCurrentDesktop()
^#NumpadDel:: RenameCurrentDesktop()

; ---- Trigger ----------------------------------------------------------------
ChordHeld() {
    return GetKeyState("Control", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
}

CheckChord() {
    if VDGrid.Naming
        return
    if ChordHeld()
        ShowOrUpdateGrid()
    else
        HideGrid()
}

; ---- Rename -----------------------------------------------------------------
RenameCurrentDesktop() {
    n := VD.getCurrentDesktopNum()

    VDGrid.Naming := true
    HideGrid() ; get the HUD out of the way of the dialog

    ib := InputBox("Enter a name for desktop " n ":", "Rename desktop " n, "w300 h130", DesktopName(n))

    VDGrid.Naming := false
    if (ib.Result = "OK")
        VD.setNameToDesktopNum(ib.Value, n)
    ; Next time the grid shows it rebuilds from scratch (HideGrid reset ShownFor),
    ; so the new name appears automatically.
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

; ---- Grid rendering ---------------------------------------------------------
ShowOrUpdateGrid() {
    current := VD.getCurrentDesktopNum()

    ; Already showing and highlight is current -> nothing to do.
    if (VDGrid.Hud && VDGrid.ShownFor = current)
        return

    if VDGrid.Hud
        VDGrid.Hud.Destroy()

    count := VD.getCount()

    g := Gui("-Caption +AlwaysOnTop +ToolWindow +E0x08000000") ; E0x08000000 = WS_EX_NOACTIVATE
    g.BackColor := VDGrid.ColBg

    ; Rows top->bottom hold 7-9, 4-6, 1-3 so 1 lands bottom-left, 9 top-right.
    Loop 3 {
        r := A_Index - 1
        Loop 3 {
            c := A_Index - 1
            n := (2 - r) * 3 + (c + 1)

            if (n = current) {
                bg := VDGrid.ColCurrent
                fg := VDGrid.TxtCurrent
            } else if (n <= count) {
                bg := VDGrid.ColExists
                fg := VDGrid.TxtExists
            } else {
                bg := VDGrid.ColMissing
                fg := VDGrid.TxtMissing
            }

            x := VDGrid.Pad + c * (VDGrid.CellW + VDGrid.Gap)
            y := VDGrid.Pad + r * (VDGrid.CellH + VDGrid.Gap)

            ; Number (top portion of the cell).
            g.SetFont("s20 Bold", "Segoe UI")
            g.Add("Text", Format("x{} y{} w{} h{} Center +0x200 Background{} c{}", x, y, VDGrid.CellW, VDGrid.NumH, bg, fg), n)

            ; Name (bottom strip). Only existing desktops; ellipsis if too long.
            name := (n <= count) ? DesktopName(n) : ""
            g.SetFont("s8 Norm", "Segoe UI")
            g.Add("Text", Format("x{} y{} w{} h{} Center +0x4280 Background{} c{}", x, y + VDGrid.NumH, VDGrid.CellW, VDGrid.CellH - VDGrid.NumH, bg, fg), name)
        }
    }

    w := VDGrid.Pad * 2 + 3 * VDGrid.CellW + 2 * VDGrid.Gap
    h := VDGrid.Pad * 2 + 3 * VDGrid.CellH + 2 * VDGrid.Gap

    ; Center on the primary monitor.
    MonitorGet(MonitorGetPrimary(), &mLeft, &mTop, &mRight, &mBottom)
    px := mLeft + ((mRight - mLeft) - w) // 2
    py := mTop + ((mBottom - mTop) - h) // 2
    g.Show(Format("NoActivate x{} y{} w{} h{}", px, py, w, h))

    VDGrid.Hud := g
    VDGrid.ShownFor := current
}

HideGrid() {
    if !VDGrid.Hud
        return
    VDGrid.Hud.Destroy()
    VDGrid.Hud := 0
    VDGrid.ShownFor := -1
}
