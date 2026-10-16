# statusLine command for sessions running the sidebar mod on Windows: the
# PowerShell twin of statusline-feed.sh, needing neither bash nor jq.
#
# Claude Code hands the status line facts mods can't read (fast_mode, the
# prompt cache's real TTL, expiry and recache size, added dirs). This saves
# that JSON per session, where the mod reads it.
#
#   ~/.claude/state/statusline/<session_id>.json   (written atomically)
#
# -Then <path> passes the same input on to another status line program (a
# .cmd, .bat or .exe, run by cmd.exe) and prints what that prints, so the slot
# can be shared. Without -Then it prints nothing, so no status line is drawn
# under the prompt.
#
# In an Orca terminal (ORCA_PANE_KEY is set), the input also goes to Orca's
# own status line script when it's installed, as Orca's status line would do.
# It can't be named with -Then: Orca replaces a status line that names it.
#
# Claude Code cancels a run that's still going when the next update is due,
# so this saves first and passes on after: PowerShell is slow to start, and a
# save that waited on the other program would rarely get to run.

param([string]$Then)

$ErrorActionPreference = 'Stop'

# The input as raw bytes, so what's saved and passed on is exactly what came in.
$stdin = [Console]::OpenStandardInput()
$buffer = New-Object System.IO.MemoryStream
$stdin.CopyTo($buffer)
$bytes = $buffer.ToArray()

$home_ = if ($env:HOME) { $env:HOME } else { $env:USERPROFILE }

$feedDir = $null
try {
  $sid = ([System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json).session_id
  if ($sid -is [string] -and $sid -ne '' -and -not $sid.StartsWith('.') -and
      $sid.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -lt 0) {
    $feedDir = Join-Path $home_ '.claude\state\statusline'
    [System.IO.Directory]::CreateDirectory($feedDir) | Out-Null
    $file = Join-Path $feedDir "$sid.json"
    $tmp = "$file.$PID.tmp"
    try {
      [System.IO.File]::WriteAllBytes($tmp, $bytes)
      # No backup: PowerShell passes a plain $null to .NET as '', which
      # Replace rejects, so it takes [NullString]::Value.
      if ([System.IO.File]::Exists($file)) {
        [System.IO.File]::Replace($tmp, $file, [NullString]::Value)
      } else {
        try { [System.IO.File]::Move($tmp, $file) } catch { [System.IO.File]::Replace($tmp, $file, [NullString]::Value) }
      }
    } catch {
      try { [System.IO.File]::Delete($tmp) } catch {}
    }
  }
} catch {}

$orcaScript = Join-Path $home_ '.orca\agent-hooks\claude-statusline.cmd'
$toOrca = $false
if ($env:ORCA_PANE_KEY -and [System.IO.File]::Exists($orcaScript)) {
  $toOrca = $true
  # -Then naming Orca's script already runs it.
  if ($Then) {
    try {
      $toOrca = [System.IO.Path]::GetFullPath($Then) -ne [System.IO.Path]::GetFullPath($orcaScript)
    } catch {}
  }
}

# Runs a program through cmd.exe with the input on its stdin, and prints what
# it prints unless $quiet. The input goes in from a file: .NET's stdin writer
# puts a byte order mark first under the UTF-8 code page, which would make
# the JSON unreadable.
$inFile = $null
function Invoke-Next([string]$path, [bool]$quiet) {
  if (-not $script:inFile) {
    $script:inFile = Join-Path ([System.IO.Path]::GetTempPath()) "claude-sidebar-feed-$PID.json"
    [System.IO.File]::WriteAllBytes($script:inFile, $bytes)
  }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "$env:SystemRoot\System32\cmd.exe"
  # /s strips the outer quotes, leaving the paths quoted, spaces and all.
  $psi.Arguments = "/d /s /c `"`"$path`" < `"$script:inFile`"`""
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.CreateNoWindow = $true
  $next = [System.Diagnostics.Process]::Start($psi)
  if ($quiet) {
    $next.StandardOutput.ReadToEnd() | Out-Null
  } else {
    $next.StandardOutput.BaseStream.CopyTo([Console]::OpenStandardOutput())
  }
  $next.WaitForExit()
}

# What's shown is the -Then program's output when there is one, else Orca's.
try {
  if ($Then) { try { Invoke-Next $Then $false } catch {} }
  if ($toOrca) { try { Invoke-Next $orcaScript ([bool]$Then) } catch {} }
} finally {
  if ($inFile) { try { [System.IO.File]::Delete($inFile) } catch {} }
}

# Ended sessions leave their file behind; drop week-old ones now and then.
if ($feedDir -and (Get-Random -Maximum 50) -eq 0) {
  try {
    Get-ChildItem -LiteralPath $feedDir -Filter '*.json' |
      Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } |
      Remove-Item -Force
  } catch {}
}

exit 0
