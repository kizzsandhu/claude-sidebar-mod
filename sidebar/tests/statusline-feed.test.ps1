# Tests for statusline-feed.ps1 (Windows). Run from anywhere:
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File sidebar\tests\statusline-feed.test.ps1
#
# Each case runs the real feed with HOME pointed at a scratch folder holding
# stand-ins for Orca's status line script and a -Then program, which log what
# they're given. Nothing outside the scratch folder is touched.

$ErrorActionPreference = 'Stop'
$feed = Join-Path (Split-Path -Parent $PSScriptRoot) 'statusline-feed.ps1'
$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("feed-test." + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $scratch | Out-Null

$script:failures = 0
$script:cases = 0
$input_ = '{"session_id":"test-session","rate_limits":{"five_hour":{"used_percentage":1}},"model":{"id":"x"}}'

function Fail($message) { Write-Host "  FAIL: $message"; $script:failures++ }

# A .cmd that appends its stdin to <log>, then a "--" line, prints <prints>
# and exits with <code>. <first> is a line it runs before reading its stdin.
function New-StandIn($path, $log, $prints, $code = 0, $first = 'rem') {
  $body = "@echo off`r`n$first`r`n`"%SystemRoot%\System32\more.com`" >> `"$log`"`r`n>> `"$log`" echo --`r`necho $prints`r`nexit /b $code`r`n"
  [System.IO.File]::WriteAllText($path, $body)
}

# The same, reading its stdin with .NET as most status line programs do,
# where more.com would hide what chcp does to a stdin that's a file.
function New-DotNetStandIn($path, $log, $prints, $first) {
  $copy = "`$i = [Console]::OpenStandardInput(); `$o = [IO.File]::Open('$log', 'Append'); `$i.CopyTo(`$o); `$o.Close()"
  $body = "@echo off`r`n$first`r`npowershell -NoProfile -Command `"$copy`"`r`n>> `"$log`" echo.`r`n>> `"$log`" echo --`r`necho $prints`r`n"
  [System.IO.File]::WriteAllText($path, $body)
}

function Start-Case($name) {
  $script:cases++
  Write-Host "$script:cases. $name"
  $script:T = Join-Path $scratch "case$script:cases"
  New-Item -ItemType Directory -Path "$T\home\.orca\agent-hooks", "$T\bin" -Force | Out-Null
  $script:orca = "$T\home\.orca\agent-hooks\claude-statusline.cmd"
  New-StandIn $orca "$T\orca.log" 'ORCA-OUT'
  $script:other = "$T\bin\other-statusline.cmd"
  New-StandIn $other "$T\then.log" 'THEN-OUT'
}

# Runs the feed as Claude Code does: the input on stdin, output captured.
# The input goes in from a file, since writing to a process's stdin from
# PowerShell can put a byte order mark first, which Claude Code never sends.
function Invoke-Feed($stdin, $paneKey, $then) {
  $inFile = "$T\stdin.json"
  [System.IO.File]::WriteAllBytes($inFile, [System.Text.Encoding]::UTF8.GetBytes($stdin))
  $command = "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -File `"$feed`""
  if ($then) { $command += " -Then `"$then`"" }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
  # Under the UTF-8 code page, a handover through .NET's stdin writer puts a
  # byte order mark first, so every case runs under it.
  $psi.Arguments = "/d /s /c `"chcp 65001 >nul & $command < `"$inFile`"`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.EnvironmentVariables['HOME'] = "$T\home"
  $psi.EnvironmentVariables.Remove('ORCA_PANE_KEY')
  if ($null -ne $paneKey) { $psi.EnvironmentVariables['ORCA_PANE_KEY'] = $paneKey }
  $p = [System.Diagnostics.Process]::Start($psi)
  $script:out = $p.StandardOutput.ReadToEnd().Trim()
  $p.WaitForExit()
  $script:code = $p.ExitCode
}

# The log's first line, or $null when there's no log. A log that starts with
# a byte order mark gives a marked line, since Get-Content would drop it.
function Get-FirstLine($log) {
  if (-not (Test-Path -LiteralPath $log)) { return $null }
  $bytes = [System.IO.File]::ReadAllBytes($log)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { return '(byte order mark)' }
  Get-Content -LiteralPath $log -TotalCount 1
}

function Get-Calls($log) {
  if (-not (Test-Path -LiteralPath $log)) { return 0 }
  @(Get-Content -LiteralPath $log | Where-Object { $_ -eq '--' }).Count
}

function Get-Saved {
  $file = "$T\home\.claude\state\statusline\test-session.json"
  if (Test-Path -LiteralPath $file) { [System.IO.File]::ReadAllText($file) } else { $null }
}

function Test-NothingSaved {
  $dir = "$T\home\.claude\state\statusline"
  -not (Test-Path -LiteralPath $dir) -or @(Get-ChildItem -LiteralPath $dir).Count -eq 0
}

function Assert-Case($name, $out, $orcaCalls, $thenCalls, [switch]$saved, [switch]$notSaved) {
  if ($code -ne 0) { Fail "${name}: exit code $code, expected 0" }
  if ($script:out -ne $out) { Fail "${name}: printed '$script:out', expected '$out'" }
  $n = Get-Calls "$T\orca.log"
  if ($n -ne $orcaCalls) { Fail "${name}: Orca's script ran $n times, expected $orcaCalls" }
  $n = Get-Calls "$T\then.log"
  if ($n -ne $thenCalls) { Fail "${name}: the -Then program ran $n times, expected $thenCalls" }
  if ($saved -and (Get-Saved) -ne $input_) { Fail "${name}: the saved file doesn't match the input" }
  if ($notSaved -and -not (Test-NothingSaved)) { Fail "${name}: a file was saved, expected none" }
  if ($orcaCalls -gt 0 -and (Get-FirstLine "$T\orca.log") -ne $input_) { Fail "${name}: Orca's script was given different input" }
  if ($thenCalls -gt 0 -and (Get-FirstLine "$T\then.log") -ne $input_) { Fail "${name}: the -Then program was given different input" }
}

try {
  Start-Case 'outside Orca: saves, prints nothing, Orca not run'
  Invoke-Feed $input_ $null $null
  Assert-Case 'outside Orca' '' 0 0 -saved

  Start-Case "in an Orca terminal: saves, then hands the input to Orca's script"
  Invoke-Feed $input_ 'tab1:1' $null
  Assert-Case 'in Orca' 'ORCA-OUT' 1 0 -saved

  Start-Case "in an Orca terminal, Orca's script missing: saves, nothing else"
  Remove-Item -LiteralPath $orca
  Invoke-Feed $input_ 'tab1:1' $null
  Assert-Case 'no Orca script' '' 0 0 -saved

  Start-Case 'an empty ORCA_PANE_KEY counts as outside Orca'
  Invoke-Feed $input_ '' $null
  Assert-Case 'empty pane key' '' 0 0 -saved

  Start-Case '-Then outside Orca: saves, runs the program, prints what it prints'
  Invoke-Feed $input_ $null $other
  Assert-Case '-Then outside Orca' 'THEN-OUT' 0 1 -saved

  Start-Case "-Then in an Orca terminal: both run once, the -Then program's output is shown"
  Invoke-Feed $input_ 'tab1:1' $other
  Assert-Case '-Then in Orca' 'THEN-OUT' 1 1 -saved

  Start-Case "-Then naming Orca's script, in an Orca terminal: Orca's script runs once, not twice"
  Invoke-Feed $input_ 'tab1:1' $orca
  Assert-Case '-Then is Orca' 'ORCA-OUT' 1 0 -saved

  Start-Case "-Then naming Orca's script with forward slashes and other casing: still once"
  Invoke-Feed $input_ 'tab1:1' ($orca.Replace('\', '/').ToUpper())
  Assert-Case '-Then is Orca, odd path' 'ORCA-OUT' 1 0 -saved

  # Status line .cmd files often start with chcp 65001, for emoji. After
  # chcp, a program reading a stdin that's a file finds nothing left, so
  # the input has to come in on a pipe, as Claude Code gives it.
  Start-Case 'a -Then program that runs chcp first still gets the input'
  New-DotNetStandIn $other "$T\then.log" 'THEN-OUT' 'chcp 65001 >nul'
  Invoke-Feed $input_ $null $other
  Assert-Case '-Then runs chcp' 'THEN-OUT' 0 1 -saved

  Start-Case 'a -Then program that fails: the feed still exits 0'
  New-StandIn $other "$T\then.log" 'THEN-OUT' 3
  Invoke-Feed $input_ $null $other
  Assert-Case '-Then fails' 'THEN-OUT' 0 1 -saved

  Start-Case "a -Then program that doesn't exist: the feed still saves and exits 0"
  Invoke-Feed $input_ $null "$T\bin\no-such-program.cmd"
  if ($code -ne 0) { Fail "-Then missing: exit code $code" }
  if ((Get-Saved) -ne $input_) { Fail "-Then missing: the saved file doesn't match the input" }

  Start-Case 'a bad session id: nothing saved, but the input still goes to Orca and -Then'
  Invoke-Feed '{"session_id":"..\\escape","rate_limits":{}}' 'tab1:1' $other
  if ($code -ne 0) { Fail "bad id: exit code $code" }
  if (-not (Test-NothingSaved)) { Fail 'bad id: a file was saved' }
  if ((Get-Calls "$T\orca.log") -ne 1) { Fail "bad id: Orca's script didn't run once" }
  if ((Get-Calls "$T\then.log") -ne 1) { Fail "bad id: the -Then program didn't run once" }
  if ($out -ne 'THEN-OUT') { Fail "bad id: printed '$out'" }

  Start-Case "input that isn't JSON: nothing saved, exits 0"
  Invoke-Feed 'not json' $null $null
  if ($code -ne 0) { Fail "not JSON: exit code $code" }
  if (-not (Test-NothingSaved)) { Fail 'not JSON: a file was saved' }
} finally {
  Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($failures -eq 0) {
  Write-Host "All $cases cases passed (PowerShell $($PSVersionTable.PSVersion))."
} else {
  Write-Host "$failures check(s) failed across $cases cases (PowerShell $($PSVersionTable.PSVersion))."
  exit 1
}
