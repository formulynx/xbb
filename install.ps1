# Installs the xbb skill + subagents into a Claude Code config dir (Windows / PowerShell).
#
# The PowerShell twin of install.sh, for native Windows where no POSIX shell
# (WSL / Git Bash) is in play. Two modes:
#   - Clone mode: run from a local git clone (.\install.ps1) -> copies the
#     payload files from the repo into $CLAUDE_DIR.
#   - Remote mode: piped via `irm <url> | iex` with no local clone -> fetches
#     the payload files from jsDelivr and copies them into $CLAUDE_DIR.
#
# On Windows this always COPIES (never symlinks): ln-style symlinks need admin
# or Developer Mode and are unreliable, so copy is the safe default - unlike
# install.sh's clone mode, there is no symlink variant here.
# Re-running is safe (idempotent). Uninstall: download this script, then run
# `.\install.ps1 -Uninstall`.

[CmdletBinding()]
param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'

$Owner   = 'formulynx'
$Repo    = 'xbb'
$Ref     = if ($env:XBB_REF)      { $env:XBB_REF }      else { 'v0.1.11' }
$BaseUrl = if ($env:XBB_BASE_URL) { $env:XBB_BASE_URL } else { "https://cdn.jsdelivr.net/gh/$Owner/$Repo@$Ref" }

function Say($msg) { Write-Output "==> $msg" }

$ClaudeDir = if ($env:CLAUDE_DIR) { $env:CLAUDE_DIR } else { Join-Path $HOME '.claude' }
$SkillsDir = Join-Path $ClaudeDir 'skills'
$AgentsDir = Join-Path $ClaudeDir 'agents'
$SkillDir  = Join-Path $SkillsDir 'xbb'

# Payload: repo-relative source path -> destination path.
# Keep in sync with install.sh's srcs/dests arrays. codex-reviewer-cleanup.sh
# and cmux-spawn-split.sh are POSIX-only (the codex reviewer / cmux terminal
# features they support are POSIX-only, per the README) so they're not
# shipped here; team-guard.ps1 backs the Concurrency guard, which applies
# regardless of OS, so it is.
$Payload = @(
  @{ Src = 'skills/xbb/SKILL.md';          Dest = (Join-Path $SkillDir  'SKILL.md') }
  @{ Src = 'skills/xbb/scripts/team-guard.ps1'; Dest = (Join-Path $SkillDir 'scripts/team-guard.ps1') }
  @{ Src = 'agents/xbb-researcher.md';     Dest = (Join-Path $AgentsDir 'xbb-researcher.md') }
  @{ Src = 'agents/xbb-coder.md';          Dest = (Join-Path $AgentsDir 'xbb-coder.md') }
  @{ Src = 'agents/xbb-reviewer.md';       Dest = (Join-Path $AgentsDir 'xbb-reviewer.md') }
)

# Records the installed ref (remote mode only); lets re-runs skip when current.
$RefFile = Join-Path $SkillDir '.xbb-ref'
$Action  = 'installed'

if ($Uninstall) {
  Say "Removing $SkillDir"
  foreach ($p in $Payload) { Remove-Item -Force -ErrorAction SilentlyContinue $p.Dest }
  Remove-Item -Force -ErrorAction SilentlyContinue $RefFile
  $ScriptsDir = Join-Path $SkillDir 'scripts'
  if ((Test-Path $ScriptsDir) -and -not (Get-ChildItem -Force $ScriptsDir)) {
    Remove-Item -Force $ScriptsDir
  }
  if ((Test-Path $SkillDir) -and -not (Get-ChildItem -Force $SkillDir)) {
    Remove-Item -Force $SkillDir
  }
  Write-Output 'xbb uninstalled.'
  return
}

Say "Target: $SkillDir"

# Clone mode when run from a checkout that actually contains the payload;
# otherwise (e.g. `irm ... | iex`, where $PSScriptRoot is empty) remote mode.
$RepoDir = $PSScriptRoot
$LocalSkill = if ($RepoDir) { Join-Path $RepoDir 'skills/xbb/SKILL.md' } else { $null }

if ($RepoDir -and (Test-Path $LocalSkill)) {
  Say "Installing xbb $Ref"
  Say "Mode: local clone ($RepoDir) - copying"
  New-Item -ItemType Directory -Force -Path $SkillsDir, $AgentsDir, (Join-Path $SkillDir 'scripts') | Out-Null
  foreach ($p in $Payload) {
    Copy-Item -Force -Path (Join-Path $RepoDir $p.Src) -Destination $p.Dest
  }
  # A clone copy tracks the working tree, not a released ref.
  Remove-Item -Force -ErrorAction SilentlyContinue $RefFile
} else {
  $Current = if (Test-Path $RefFile) { (Get-Content $RefFile -Raw).Trim() } else { '' }
  if ($Current -eq $Ref) {
    Say "xbb $Ref is already installed - nothing to do."
    return
  }
  if ($Current) { Say "Updating xbb from $Current to $Ref"; $Action = 'updated' }
  else          { Say "Installing xbb $Ref" }
  Say "Mode: remote - downloading from $BaseUrl"
  New-Item -ItemType Directory -Force -Path $SkillsDir, $AgentsDir, (Join-Path $SkillDir 'scripts') | Out-Null
  # TLS 1.2 for Windows PowerShell 5.1, whose default may be too old for the CDN.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  foreach ($p in $Payload) {
    Say "Fetching $($p.Src)"
    Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/$($p.Src)" -OutFile $p.Dest
  }
  Set-Content -Path $RefFile -Value $Ref
}

Write-Output "xbb $Ref $Action successfully.`n`nRestart Claude Code (or start a new session) to pick it up."
