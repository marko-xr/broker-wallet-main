<#
  Broker Wallet — Offer / Owner land-plan attachment staging acceptance launcher.

  Run by the owner, in the owner's own terminal, against the STAGING Worker
  only. It takes the staging gate key and the two test accounts' credentials
  from the local environment (falling back to masked prompts), gives them to
  the Node runner for this one run only, and clears its copies afterwards.
  Nothing secret is written to disk or printed.

  It reads the same settings as the Quotation launcher, so a machine that can
  run that one can run this one (process scope first, then User scope):
    BW_E2E_STAGING_KEY                       the staging gate key
    BW_TEST_EMAIL / BW_TEST_PASSWORD         account A, the designated test-only
                                             account (BW_TEST_USER_ID is checked
                                             by the runner against its uid)
    BW_TEST_B_EMAIL / BW_TEST_B_PASSWORD     account B, a second test-only
                                             account (BW_TEST_B_USER_ID, when set,
                                             is checked against its uid)

  Account A must be the designated test account. Account B must be a different
  test-only account.

  Single Active Device: the run CLAIMS the active app session for each account it
  signs in with, which ends every other session of that account. The launcher
  asks you to type CLAIM first, and the runner refuses to start without that
  acknowledgement.

  The run creates its own test Offers and Owners and plans, removes every plan and
  upload it made, and soft-deletes its test records at the end. The report goes to
  reports\plan_attachment_<run id>.json (gitignored) and holds no secret.
#>
param(
  [string] $WorkerUrl = 'https://r2-profile-upload-staging.mohammed-developer-code.workers.dev'
)

$ErrorActionPreference = 'Stop'

function Confirm-SessionClaim([string] $Accounts) {
  Write-Host ''
  Write-Host "This run CLAIMS the active Broker Wallet app session for $Accounts (Single Active Device)."
  Write-Host 'Claiming ends every other session of the same account: a phone or emulator signed in to'
  Write-Host 'one of them is signed out. Use disposable or designated test-only accounts, never a real user.'
  $answer = Read-Host 'Type CLAIM to continue'
  if ($answer -cne 'CLAIM') { throw 'Cancelled: the session claim was not acknowledged. Nothing was run.' }
  $env:BW_E2E_ACK_SESSION_CLAIM = '1'
}

function Get-Setting([string] $Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
  $value
}

function Read-Secret([string] $Prompt) {
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function Get-OrAsk([string] $Name, [string] $Prompt, [switch] $Secret) {
  $value = Get-Setting $Name
  if ($value) { return $value }
  if ($Secret) { return Read-Secret $Prompt }
  Read-Host -Prompt $Prompt
}

$code = 1
try {
  Confirm-SessionClaim 'account A (the designated test account) and account B (the second test account)'
  $env:BW_E2E_WORKER_URL = $WorkerUrl
  $env:BW_E2E_STAGING_KEY = Get-OrAsk 'BW_E2E_STAGING_KEY' 'Staging gate key' -Secret
  $env:BW_E2E_A_EMAIL = Get-OrAsk 'BW_TEST_EMAIL' 'Account A email (the designated test account)'
  $env:BW_E2E_A_PASSWORD = Get-OrAsk 'BW_TEST_PASSWORD' 'Account A password' -Secret
  $aUid = Get-Setting 'BW_TEST_USER_ID'
  if ($aUid) { $env:BW_E2E_A_UID = $aUid }
  $env:BW_E2E_B_EMAIL = Get-OrAsk 'BW_TEST_B_EMAIL' 'Account B email (the second test account)'
  $env:BW_E2E_B_PASSWORD = Get-OrAsk 'BW_TEST_B_PASSWORD' 'Account B password' -Secret
  $bUid = Get-Setting 'BW_TEST_B_USER_ID'
  if ($bUid) { $env:BW_E2E_B_UID = $bUid }

  node (Join-Path $PSScriptRoot 'plan_attachment_staging_acceptance.mjs')
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_E2E_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
