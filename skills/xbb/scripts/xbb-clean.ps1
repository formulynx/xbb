# xbb-clean (PowerShell twin of xbb-clean.sh -- see that file for the
# unattended-deletion caveat, not repeated here): mechanical accounting and
# deletion for /xbb's `clean` mode.
#
# Usage:
#   xbb-clean.ps1 measure
#   xbb-clean.ps1 delete

param(
  [Parameter(Mandatory=$true, Position=0)][ValidateSet('measure','delete')][string]$Cmd
)

$R = if ($env:TMPDIR) { $env:TMPDIR } elseif ($env:TEMP) { $env:TEMP } elseif ($env:TMP) { $env:TMP } else { 'C:\Temp' }

$dirs = @(Get-ChildItem -Path $R -Directory -Filter 'xbb-run-*' -ErrorAction SilentlyContinue)

if ($dirs.Count -eq 0) {
  Write-Output "nothing to clean"
  exit 0
}

switch ($Cmd) {
  'measure' {
    $total = 0
    foreach ($d in $dirs) {
      $size = (Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      if (-not $size) { $size = 0 }
      $total += $size
      Write-Output ("{0,10:N0}  {1}" -f $size, $d.FullName)
    }
    Write-Output ("Total: {0:N0} bytes across {1} dir(s)" -f $total, $dirs.Count)
  }
  'delete' {
    $total = 0
    foreach ($d in $dirs) {
      $size = (Get-ChildItem -Path $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
      if (-not $size) { $size = 0 }
      $total += $size
      Remove-Item -LiteralPath $d.FullName -Recurse -Force
    }
    Write-Output ("Deleted {0} dir(s), freed {1:N0} bytes" -f $dirs.Count, $total)
  }
}
