<#
.SYNOPSIS
  Runs `swift build` on Windows with the given arguments, trying again when Swift Build reports a file in use.

.DESCRIPTION
  Swift Build on Windows can fail to touch a test bundle whose Info.plist another of its tasks still holds open ("The
  process cannot access the file because it is being used by another process", docs/windows-port/DECISIONS.md D-032).
  Only then is the build tried again, up to three attempts in all; any other failure ends it at once. Output goes to the
  console and, with -Log, is added to that file; the exit status is the last attempt's.

.EXAMPLE
  scripts\windows\build.ps1 -c release
  scripts\windows\build.ps1 -Log "$env:TEMP\g3.log" --build-tests --scratch-path "$env:LOCALAPPDATA\agenthud-dev\build"
#>
# The arguments are read as they are, so that swift's own options (`-c release`) pass through unparsed.
$Log = ""
$SwiftArguments = @($args)
if ($SwiftArguments.Count -ge 2 -and $SwiftArguments[0] -eq '-Log') {
    $Log = $SwiftArguments[1]
    $SwiftArguments = @($SwiftArguments | Select-Object -Skip 2)
}

# swift writes its progress to standard error, which Windows PowerShell would otherwise turn into a stopping error.
$ErrorActionPreference = 'Continue'
$status = 1
foreach ($attempt in 1..3) {
    $script:busy = $false
    & swift build @SwiftArguments 2>&1 | ForEach-Object {
        $line = "$_"
        Write-Host $line
        if ($line -match 'being used by another process') { $script:busy = $true }
        if ($Log) { Add-Content -LiteralPath $Log -Value $line -Encoding utf8 }
    }
    $status = $LASTEXITCODE
    if ($status -eq 0 -or -not $script:busy) { break }
    Write-Host "swift build hit a file in use (attempt $attempt of 3)"
}
exit $status
