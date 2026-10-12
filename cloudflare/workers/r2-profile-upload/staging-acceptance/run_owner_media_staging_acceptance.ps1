<#
  Broker Wallet — Owner private media staging acceptance launcher.

  Run by the owner, in the owner's own terminal, against the STAGING Worker
  only. Asks for the staging gate key and the test accounts' credentials with
  masked input, gives them to the Node runner for this one run only, and
  clears them afterwards. Nothing secret is written to disk or printed.

  Accounts: A and B are two different, fresh, disposable test accounts. Use
  the same two accounts for -Mode F1Verify as for the Full run it follows.

  Single Active Device: the run CLAIMS the active app session for each account it
  signs in with, which ends every other session of that account. The launcher
  asks you to type CLAIM first, and the runner refuses to start without that
  acknowledgement.

  -Mode Full      (default) the whole acceptance; needs -VideoPath (MP4, MOV or
                  3GP, at most 3:00 and 100 MB). Writes reports\f1_state_*.json.
  -Mode F1Verify  phase 2 of the F1 check, at least 24 h 10 min after the Full
                  run; needs -F1StatePath (that state file).
#>
param(
  [Parameter(Mandatory = $true)] [string] $WorkerUrl,
  [ValidateSet('Full', 'F1Verify')] [string] $Mode = 'Full',
  [string] $VideoPath,
  [string] $LongVideoPath,
  [string] $F1StatePath
)

$ErrorActionPreference = 'Stop'

function Read-Secret([string] $Prompt) {
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Confirm-SessionClaim([string] $Accounts) {
  Write-Host ''
  Write-Host "This run CLAIMS the active Broker Wallet app session for $Accounts (Single Active Device)."
  Write-Host 'Claiming ends every other session of the same account: a phone or emulator signed in to'
  Write-Host 'one of them is signed out. Use disposable or designated test-only accounts, never a real user.'
  $answer = Read-Host 'Type CLAIM to continue'
  if ($answer -cne 'CLAIM') { throw 'Cancelled: the session claim was not acknowledged. Nothing was run.' }
  $env:BW_E2E_ACK_SESSION_CLAIM = '1'
}

if ($Mode -eq 'Full') {
  if (-not $VideoPath) { throw '-VideoPath is required for -Mode Full.' }
  if (-not (Test-Path -LiteralPath $VideoPath)) { throw "Video not found: $VideoPath" }
  if ($LongVideoPath -and -not (Test-Path -LiteralPath $LongVideoPath)) { throw "Long video not found: $LongVideoPath" }
} else {
  if (-not $F1StatePath) { throw '-F1StatePath is required for -Mode F1Verify.' }
  if (-not (Test-Path -LiteralPath $F1StatePath)) { throw "F1 state file not found: $F1StatePath" }
}

$code = 1
try {
  Confirm-SessionClaim 'account A and account B (two fresh, disposable accounts)'
  $env:BW_E2E_WORKER_URL = $WorkerUrl
  if ($Mode -eq 'Full') {
    $env:BW_E2E_MODE = 'full'
    $env:BW_E2E_VIDEO_PATH = (Resolve-Path -LiteralPath $VideoPath).Path
    if ($LongVideoPath) { $env:BW_E2E_LONG_VIDEO_PATH = (Resolve-Path -LiteralPath $LongVideoPath).Path }
  } else {
    $env:BW_E2E_MODE = 'f1-verify'
    $env:BW_E2E_F1_STATE = (Resolve-Path -LiteralPath $F1StatePath).Path
  }

  $env:BW_E2E_STAGING_KEY = Read-Secret 'Staging gate key'
  $env:BW_E2E_A_EMAIL = Read-Host 'Account A email (fresh, disposable)'
  $env:BW_E2E_A_PASSWORD = Read-Secret 'Account A password'
  $env:BW_E2E_B_EMAIL = Read-Host 'Account B email (a different fresh, disposable account)'
  $env:BW_E2E_B_PASSWORD = Read-Secret 'Account B password'

  node (Join-Path $PSScriptRoot 'owner_media_staging_acceptance.mjs')
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_E2E_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
