# xbb resolve-team-file (PowerShell twin of resolve-team-file.sh -- see that
# file for the design note): prints the team config.json path for a Claude
# Code session id. Pure computation, no file I/O beyond printing.
#
# Usage:
#   resolve-team-file.ps1 <session-id>

param(
  [Parameter(Mandatory=$true, Position=0)][string]$SessionId
)

$short = $SessionId.Substring(0, [Math]::Min(8, $SessionId.Length))
Write-Output (Join-Path $env:USERPROFILE ".claude\teams\session-$short\config.json")
