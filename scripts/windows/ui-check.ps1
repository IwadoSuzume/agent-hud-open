<#
.SYNOPSIS
  The shell's behaviour on a real desktop (docs/hud.md, Approvals), with the engine's demo: the island never takes the
  focus when it starts or when a queued line is clicked; a question is answered one page at a time (Next disabled until
  there is an answer, Skip and Submit), a plan is approved, and each leaves the engine's queue; a field takes the keyboard
  only once clicked, keeps it through Next, and gives it back to the app that had it when the answers are sent.

.DESCRIPTION
  It moves the pointer, clicks and types (Unicode SendInput, which no input method composes), so run it on a desktop
  nobody is using, never on someone's working session. Opt-in, beside gate G5 (PROGRESS.md); exits 1 on the first
  failed check. The demo writes its settings into a temporary profile (D-021).

.EXAMPLE
  scripts\windows\ui-check.ps1 -Engine "$env:LOCALAPPDATA\agenthud-dev\build\out\Products\Release-windows-x86_64\agenthud-engine.exe"
#>
param([Parameter(Mandatory = $true)] [string] $Engine)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$shell = Join-Path $root 'windows\AgentHUD\bin\Release\net10.0-windows\AgentHUD.exe'
if (-not (Test-Path -LiteralPath $shell)) { throw "build windows\AgentHUD in Release first ($shell)" }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class UiCheckInput {
  [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort vk; public ushort scan; public uint flags; public uint time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit, Size = 40)] struct INPUT { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KEYBDINPUT ki; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  public static uint ForegroundPid() { uint p; GetWindowThreadProcessId(GetForegroundWindow(), out p); return p; }
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
  /// A press at one point, the pointer moved in steps, and the release at the other.
  public static void Drag(int x0, int y0, int x1, int y1) {
    // A moment over the dock first, as a hand would rest there, so the window under the pointer is known before the press.
    SetCursorPos(x0, y0); System.Threading.Thread.Sleep(300); mouse_event(2, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(100);
    for (int i = 1; i <= 20; i++) { SetCursorPos(x0 + (x1 - x0) * i / 20, y0 + (y1 - y0) * i / 20); System.Threading.Thread.Sleep(25); }
    mouse_event(4, 0, 0, 0, IntPtr.Zero);
  }
  static void Key(ushort vk, ushort scan, uint flags) {
    var down = new INPUT { type = 1, ki = new KEYBDINPUT { vk = vk, scan = scan, flags = flags } };
    var up = new INPUT { type = 1, ki = new KEYBDINPUT { vk = vk, scan = scan, flags = flags | 2 } };
    SendInput(2, new[] { down, up }, Marshal.SizeOf<INPUT>());
    System.Threading.Thread.Sleep(30);
  }
  public static void Type(string text) { foreach (var c in text) Key(0, c, 4); }
  public static void Enter() { Key(0x0D, 0, 0); }
}
'@

$failures = 0
function Check([bool] $ok, [string] $what) {
    if ($ok) { Write-Host "PASS $what" } else { Write-Host "FAIL $what"; $script:failures++ }
}

$profileRoot = Join-Path ([IO.Path]::GetTempPath()) ("agenthud-uicheck-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $profileRoot 'Roaming'), (Join-Path $profileRoot 'Local') | Out-Null
$realRoaming = $env:APPDATA; $realLocal = $env:LOCALAPPDATA
$env:APPDATA = Join-Path $profileRoot 'Roaming'; $env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
$before = [UiCheckInput]::ForegroundPid()
$process = Start-Process -FilePath $shell -PassThru -ArgumentList @('--demo', '--engine', "`"$Engine`"", '--language', 'en')
$env:APPDATA = $realRoaming; $env:LOCALAPPDATA = $realLocal
try {
    Start-Sleep -Seconds 5
    $desktop = [Windows.Automation.AutomationElement]::RootElement
    $mine = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty), $process.Id
    function All { $desktop.FindAll([Windows.Automation.TreeScope]::Descendants, $mine) }
    function Named($text) { All | Where-Object { $_.Current.Name -eq $text } | Select-Object -First 1 }
    function Line($text) {
        All | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and
            ($_.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.Name -eq $text }) } |
            Select-Object -First 1
    }
    function ClickOn($element) {
        $r = $element.Current.BoundingRectangle
        [UiCheckInput]::Click([int]($r.X + [Math]::Min(40, $r.Width / 2)), [int]($r.Y + $r.Height / 2))
        Start-Sleep -Milliseconds 700
    }

    Check ([UiCheckInput]::ForegroundPid() -eq $before) 'starting takes no focus'
    $line = Line 'Which database?'
    Check ([bool]$line) 'the question waits in the queue'
    ClickOn $line
    Check ([UiCheckInput]::ForegroundPid() -eq $before) 'clicking a queued line takes no focus'
    Check (-not (Named 'Next').Current.IsEnabled) 'Next waits for an answer'
    ClickOn (Line 'SQLite')
    Check ((Named 'Next').Current.IsEnabled) 'an offered answer makes Next ready'
    Check ([UiCheckInput]::ForegroundPid() -eq $before) 'picking an answer takes no focus'

    $field = All | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::Edit -and -not $_.Current.IsOffscreen } | Select-Object -First 1
    ClickOn $field
    Check ([UiCheckInput]::ForegroundPid() -eq $process.Id) 'clicking the field takes the keyboard'
    # A Chinese character too, written as its code so the script reads the same in any code page.
    $answer = "Postgres, $([char]0x7528) SQLite later"
    [UiCheckInput]::Type($answer)
    Start-Sleep -Milliseconds 400
    $value = $field.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value
    Check ($value -eq $answer) 'the field holds what was typed'
    [UiCheckInput]::Enter()
    Start-Sleep -Milliseconds 700
    Check ([bool](Named 'Submit')) 'Enter goes on to the next question'
    Check ([UiCheckInput]::ForegroundPid() -eq $process.Id) 'the keyboard stays through Next'
    [UiCheckInput]::Type('no')
    [UiCheckInput]::Enter()
    Start-Sleep -Milliseconds 1500
    Check (-not (Line 'Which database?') -and -not (Named 'Submit')) 'the answers are sent and the question leaves'
    Check ([UiCheckInput]::ForegroundPid() -eq $before) 'the keyboard goes back to the app that had it'

    $plan = Line 'Plan'
    Check ([bool]$plan) 'the plan waits in the queue'
    if ($plan) {
        ClickOn $plan
        ClickOn (Named 'Approve')
        Start-Sleep -Milliseconds 1200
        Check (-not (Line 'Plan')) 'an approved plan leaves'
    }
} finally {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# Settings: a change goes to the engine, which saves it (the demo's own settings file); switching the hooks off asks.
$demoSettings = Join-Path $profileRoot 'Roaming\Agent HUD Open\settings.demo.json'
# The demo keeps its settings as swift-corelibs' defaults do: Core's encoding, base64, under `settings.v1`.
function SavedSettings {
    if (-not (Test-Path -LiteralPath $demoSettings)) { return $null }
    $defaults = Get-Content -Raw -LiteralPath $demoSettings | ConvertFrom-Json
    $data = $defaults.values.'settings.v1'.data._0
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($data)) | ConvertFrom-Json
}
$env:APPDATA = Join-Path $profileRoot 'Roaming'; $env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
$process = Start-Process -FilePath $shell -PassThru -ArgumentList @('--demo', '--show-settings', '--engine', "`"$Engine`"", '--language', 'en')
$env:APPDATA = $realRoaming; $env:LOCALAPPDATA = $realLocal
try {
    Start-Sleep -Seconds 5
    $mine = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty), $process.Id
    function Id($id) { All | Where-Object { $_.Current.AutomationId -eq $id } | Select-Object -First 1 }
    $wait = Id 'WaitChoice'
    Check ([bool]$wait) '--show-settings opens the settings window'
    if ($wait) {
        $wait.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 500
        $five = All | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::ListItem -and $_.Current.Name -eq '5 minutes' } | Select-Object -First 1
        Check ([bool]$five) "the wait's choices are the engine's words"
        if ($five) { ClickOn $five }
        Start-Sleep -Milliseconds 1500
        $saved = SavedSettings
        Check ($saved.approvalWaitMinutes -eq 5) 'the engine saved the wait the window chose'
        $hooks = Id 'ClientHooks'
        ClickOn $hooks
        Start-Sleep -Milliseconds 800
        # The settings window owns the dialog, and UI Automation lists it under its owner.
        $confirm = All | Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::Window -and $_.Current.Name -eq 'Remove client hooks?' } | Select-Object -First 1
        Check ([bool]$confirm) 'switching the hooks off asks first'
        if ($confirm) {
            $cancel = $confirm.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition) |
                Where-Object { $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and $_.Current.Name -eq 'Cancel' } | Select-Object -First 1
            ClickOn $cancel
            Start-Sleep -Milliseconds 800
        }
        $state = $hooks.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern).Current.ToggleState
        $saved = SavedSettings
        Check ($state -eq [Windows.Automation.ToggleState]::On -and $saved.clientHooks -eq $true) 'Cancel keeps the hooks on'
    }
} finally {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# The dock: dragged on the primary display to its left edge, it goes there, and the engine keeps it there (D-051).
Add-Type -AssemblyName System.Windows.Forms
$env:APPDATA = Join-Path $profileRoot 'Roaming'; $env:LOCALAPPDATA = Join-Path $profileRoot 'Local'
$process = Start-Process -FilePath $shell -PassThru -ArgumentList @('--demo', '--engine', "`"$Engine`"", '--language', 'en')
$env:APPDATA = $realRoaming; $env:LOCALAPPDATA = $realLocal
try {
    Start-Sleep -Seconds 5
    $mine = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ProcessIdProperty), $process.Id
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    function PrimaryMarks {
        All | Where-Object { $_.Current.AutomationId -eq 'MarksList' } | Where-Object {
            $r = $_.Current.BoundingRectangle
            $r.X -ge $screen.Left -and $r.X -lt $screen.Right -and $r.Y -ge $screen.Top -and $r.Y -lt $screen.Bottom
        } | Select-Object -First 1
    }
    $marks = PrimaryMarks
    Check ([bool]$marks) 'the dock rests on the primary display'
    if ($marks) {
        $r = $marks.Current.BoundingRectangle
        Check ([Math]::Abs(($r.X + $r.Width / 2) - ($screen.Left + $screen.Width / 2)) -lt 40 -and $r.Y -lt $screen.Top + 60) "it starts at the top centre, Core's default"
        $toY = [int]($screen.Top + $screen.Height * 0.3)
        [UiCheckInput]::Drag([int]($r.X + 12), [int]($r.Y + $r.Height / 2), $screen.Left + 3, $toY)
        Start-Sleep -Milliseconds 1500
        $moved = (PrimaryMarks).Current.BoundingRectangle
        Check ($moved.X -lt $screen.Left + 60 -and [Math]::Abs(($moved.Y + $moved.Height / 2) - $toY) -lt $screen.Height * 0.1) 'the drop puts it on the left edge where it was let go'
        $saved = SavedSettings
        $placements = @($saved.screens.PSObject.Properties | ForEach-Object { $_.Value })
        Check ($placements.Count -eq 1 -and $placements[0].edge -eq 'left' -and [Math]::Abs($placements[0].offset - 0.3) -lt 0.05) 'the engine keeps the display on the left edge'
    }
} finally {
    Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item -Recurse -Force $profileRoot -ErrorAction SilentlyContinue
}
if ($failures) { Write-Host "$failures check(s) failed"; exit 1 }
Write-Host 'UI check: every check passed.'
