; =============================================================================
; VD-grid.ahk
; A numpad-layout 3x3 HUD of virtual desktops 1-9, shown while Ctrl+Win is held.
; Purely informational - highlights the current desktop. Navigation itself stays
; on the existing Ctrl+Win+Numpad hotkeys (see VD-combined.ahk / VD-numpad-desktops.ahk).
;
; Layout (numpad style):   7 8 9
;                          4 5 6
;                          1 2 3
;
; Standalone for now (run it alongside the rest); can be folded into VD-combined later.
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

#Include ../VD.ahk/VD.ah2
;#SETUP END

; ---- Config + state ---------------------------------------------------------
; Held in a class so it's reliably accessible from every function (avoids the
; v2 "local variable not assigned / global declaration required" pitfall).
; Defined before the auto-execute body so its static init isn't flagged as
; unreachable (which a class after `return` would be).
class VDGrid {
    ; Appearance - tweak here.
    static Cell := 64           ; cell size (px)
    static Gap  := 8            ; gap between cells
    static Pad  := 12           ; window padding
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
}

VD.createUntil(3)

; Poll for the Ctrl+Win chord. A lightweight always-on timer is far more robust
; than hooking the modifier keys, and never interferes with other hotkeys.
SetTimer CheckChord, 75

return

; ---- Trigger ----------------------------------------------------------------
ChordHeld() {
    return GetKeyState("Control", "P") && (GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
}

CheckChord() {
    if ChordHeld()
        ShowOrUpdateGrid()
    else
        HideGrid()
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
    g.SetFont("s22 Bold", "Segoe UI")

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

            x := VDGrid.Pad + c * (VDGrid.Cell + VDGrid.Gap)
            y := VDGrid.Pad + r * (VDGrid.Cell + VDGrid.Gap)
            g.Add("Text", Format("x{} y{} w{} h{} Center +0x200 Background{} c{}", x, y, VDGrid.Cell, VDGrid.Cell, bg, fg), n)
        }
    }

    w := VDGrid.Pad * 2 + 3 * VDGrid.Cell + 2 * VDGrid.Gap
    h := w

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
