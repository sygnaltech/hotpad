param(
    [Parameter(Position = 0)]
    [string]$Type = "problem",

    # Workspace folder whose VS Code window we want to locate.
    # Defaults to the current working directory (the folder Claude is operating in).
    [string]$Workspace = "",

    [string]$Message = ""
)

# ---------------------------------------------------------------------------
# 1. Play the audible alert (tones mirror the `notify` skill so they're
#    instantly recognizable and cut through other audio).
# ---------------------------------------------------------------------------
switch ($Type.ToLower()) {
    "problem"   { [console]::beep(880, 180); [console]::beep(587, 320) }
    "attention" { [console]::beep(1000, 140); Start-Sleep -Milliseconds 80; [console]::beep(1000, 140) }
    "success"   { [console]::beep(523, 130); [console]::beep(659, 130); [console]::beep(784, 220) }
    "tick"      { [console]::beep(440, 90) }
    default     { [console]::beep(800, 400) }
}

if ($Message) { Write-Output "[alert:$Type] $Message" }

# ---------------------------------------------------------------------------
# 2. Resolve the workspace leaf used to match the VS Code window title.
#    VS Code titles look like: "<file> - <folder> - Visual Studio Code".
# ---------------------------------------------------------------------------
if (-not $Workspace) { $Workspace = (Get-Location).Path }
$leaf = Split-Path $Workspace -Leaf

# ---------------------------------------------------------------------------
# 3. Define IVirtualDesktopManager — the PUBLIC, stable COM interface.
#    GetWindowDesktopId / IsWindowOnCurrentVirtualDesktop only need this;
#    no undocumented internal interface required.
# ---------------------------------------------------------------------------
if (-not ("Hotpad.VDM" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Hotpad {
    [ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IVirtualDesktopManager {
        [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out int onCurrentDesktop);
        [PreserveSig] int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
        [PreserveSig] int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }

    [ComImport, Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a")]
    public class CVirtualDesktopManager { }

    // Do the COM calls inside C#: PowerShell binds RCW methods against the
    // coclass, not the interface, so calling the interface methods from PS fails.
    public static class VDM {
        static IVirtualDesktopManager Mgr() {
            return (IVirtualDesktopManager)(new CVirtualDesktopManager());
        }
        public static Guid GetDesktopId(IntPtr hwnd) {
            Guid g; Mgr().GetWindowDesktopId(hwnd, out g); return g;
        }
        public static bool IsOnCurrent(IntPtr hwnd) {
            int o; Mgr().IsWindowOnCurrentVirtualDesktop(hwnd, out o); return o != 0;
        }
    }
}
'@
}

# ---------------------------------------------------------------------------
# 4. Find the VS Code window for this workspace (title contains the leaf).
# ---------------------------------------------------------------------------
$proc = Get-Process -Name Code -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$leaf*" } |
        Select-Object -First 1

if (-not $proc) {
    Write-Output "Could not find a VS Code window whose title contains '$leaf'."
    Write-Output "(Workspace: $Workspace)"
    return
}
$hwnd = $proc.MainWindowHandle

# ---------------------------------------------------------------------------
# 5. Query the virtual desktop for that window.
# ---------------------------------------------------------------------------
$guid = [Hotpad.VDM]::GetDesktopId($hwnd)
$onCurrent = [Hotpad.VDM]::IsOnCurrent($hwnd)

# ---------------------------------------------------------------------------
# 6. Map the desktop GUID -> human name + ordinal index, both from the
#    registry (no undocumented API). Names: Desktops\{GUID}\Name.
#    Live ordering: the VirtualDesktopIDs blob (concatenated 16-byte GUIDs).
# ---------------------------------------------------------------------------
$base   = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops"
$guidB  = $guid.ToString("B").ToUpper()

$name = $null
$nameKey = "$base\Desktops\$guidB"
if (Test-Path $nameKey) {
    $name = (Get-ItemProperty $nameKey -Name Name -ErrorAction SilentlyContinue).Name
}

$index = $null
$total = $null
$ids = (Get-ItemProperty $base -Name VirtualDesktopIDs -ErrorAction SilentlyContinue).VirtualDesktopIDs
if ($ids) {
    $total = [int]($ids.Length / 16)
    for ($i = 0; $i -lt $total; $i++) {
        $g = [Guid]::new([byte[]]($ids[($i * 16)..($i * 16 + 15)]))
        if ($g -eq $guid) { $index = $i + 1; break }
    }
}

# ---------------------------------------------------------------------------
# 7. Report.
# ---------------------------------------------------------------------------
$label = if ($name) { "$name" } else { "(unnamed)" }
$pos   = if ($index) { "Desktop $index of $total" } else { "unknown position" }

Write-Output ""
Write-Output "=== hotpad alert ==="
Write-Output ("Workspace  : {0}  ({1})" -f $leaf, $Workspace)
Write-Output ("VS Code    : {0}" -f $proc.MainWindowTitle)
Write-Output ("            : pid {0}, hwnd 0x{1:X}" -f $proc.Id, [int64]$hwnd)
Write-Output ("Desktop    : {0}  [{1}]" -f $label, $pos)
Write-Output ("GUID       : {0}" -f $guidB)
Write-Output ("On current : {0}" -f $(if ($onCurrent) { "yes - you're looking at this desktop" } else { "NO - alert is from another desktop" }))
