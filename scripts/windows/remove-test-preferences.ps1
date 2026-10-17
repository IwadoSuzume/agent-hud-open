<#
.SYNOPSIS
  Removes the preference files the Core tests leave in %LOCALAPPDATA% on Windows.

.DESCRIPTION
  On Windows, swift-corelibs-foundation keeps every UserDefaults(suiteName:) domain as <suite>.plist directly in the
  user's local application data folder, which it finds through the shell's known folder whatever LOCALAPPDATA says,
  so a temporary profile cannot catch them (docs/windows-port/DECISIONS.md D-021). Some tests do not remove the
  domain they made. This removes exactly those files: names made of a test's suite prefix and a UUID, written since
  -Since, and nothing else. The application itself never writes there (it keeps settings.json, D-018).
#>
param(
    [Parameter(Mandatory = $true)] [datetime] $Since
)

$folder = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$uuid = '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
# The suite names the Core tests use: a test class's name, an optional part, then a UUID; or one fixed name.
$pattern = "^(?:(?:AgentHUD[A-Za-z]*|[A-Z][A-Za-z]*Tests)(?:\.[A-Za-z]+)*\.$uuid(?:\.[A-Za-z]+)?|DemoClockTests)\.plist$"

$removed = 0
Get-ChildItem -LiteralPath $folder -File -Filter '*.plist' |
    Where-Object { $_.Name -cmatch $pattern -and $_.CreationTime -ge $Since } |
    ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Force
        $removed++
    }
"Removed $removed test preference file(s) from $folder"
