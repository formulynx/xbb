# xbb team-guard (PowerShell twin of team-guard.sh -- see that file for the
# isActive-semantics caveat, not repeated here): mechanical accounting for
# maxConcurrentAgents and for finding this run's Claude-native teammates to
# stop. Never spawns or stops anything itself -- Agent (spawn) and TaskStop
# are tool calls only the orchestrator can issue.
#
# Usage:
#   team-guard.ps1 count <team-file> <run-id>
#   team-guard.ps1 gate  <team-file> <run-id> <max-concurrent> <want-n>
#   team-guard.ps1 sweep <team-file> <run-id>

param(
  [Parameter(Mandatory=$true, Position=0)][ValidateSet('count','gate','sweep')][string]$Cmd,
  [Parameter(Mandatory=$true, Position=1)][string]$TeamFile,
  [Parameter(Mandatory=$true, Position=2)][string]$RunId,
  [Parameter(Position=3)][int]$Max,
  [Parameter(Position=4)][int]$Want
)

function Get-Rows {
  if (-not (Test-Path -LiteralPath $TeamFile)) { return @() }
  $cfg = Get-Content -LiteralPath $TeamFile -Raw | ConvertFrom-Json
  $infix = "-$RunId-"
  @($cfg.members | Where-Object { $_.name -ne 'team-lead' -and $_.name -like "*$infix*" } |
    ForEach-Object { [PSCustomObject]@{ Name = $_.name; Active = ($_.isActive -eq $true) } })
}

switch ($Cmd) {
  'count' {
    $rows = Get-Rows
    $active = @($rows | Where-Object Active)
    $finished = @($rows | Where-Object { -not $_.Active })
    Write-Output "ACTIVE $($active.Count)"
    Write-Output "FINISHED $($finished.Count)"
    Write-Output "ACTIVE_NAMES $(($active.Name) -join ' ')"
    Write-Output "FINISHED_NAMES $(($finished.Name) -join ' ')"
  }
  'gate' {
    if (-not $Max -or -not $Want) { Write-Error "max-concurrent and want-n required"; exit 1 }
    $rows = Get-Rows
    $activeN = @($rows | Where-Object Active).Count
    if (($activeN + $Want) -le $Max) {
      Write-Output "SPAWN $Want"
    } else {
      $need = $activeN + $Want - $Max
      $finished = @($rows | Where-Object { -not $_.Active })
      $candidates = @($finished.Name | Select-Object -First $need)
      Write-Output "HOLD need=$need candidates=$($candidates -join ' ')"
      if ($finished.Count -lt $need) {
        Write-Output "SHORTFALL $($need - $finished.Count)"
      }
    }
  }
  'sweep' {
    (Get-Rows).Name | ForEach-Object { Write-Output $_ }
  }
}
