<#
  Broker Wallet — Quotation private media PRODUCTION smoke launcher.

  Run by the owner, in the owner's own terminal, AFTER the Quotation-capable
  Worker has been promoted to Production. It targets the production Worker
  (https://media-api.brokerwallet.ae, private bucket broker-wallet-media) as the
  designated test-only account A only. There is no staging gate and no second
  account. It takes A's credentials from the local environment (process scope,
  then User scope: BW_TEST_EMAIL, BW_TEST_PASSWORD, BW_TEST_USER_ID), falls back
  to masked prompts, gives them to the Node runner for this one run only, and
  clears its copies afterwards. Nothing secret is written to disk or printed.

  The runner creates ONE temporary Quotation, one temporary Offer and one Owner
  (names start "production-smoke") and leaves them for a narrow cleanup of
  exactly the ids in its report (reports\quotation_media_production_smoke_*.json).

  Single Active Device: the run CLAIMS the active app session for account A,
  which ends every other session of that account. The launcher asks you to type
  CLAIM first, and the runner refuses to start without that acknowledgement.
#>
$ErrorActionPreference = 'Stop'

function Confirm-SessionClaim([string] $Accounts) {
  Write-Host ''
  Write-Host "This run CLAIMS the active Broker Wallet app session for $Accounts (Single Active Device)."
  Write-Host 'Claiming ends every other session of the same account: a phone or emulator signed in to'
  Write-Host 'it is signed out. Use the designated test-only account, never a real user.'
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

$code = 1
try {
  Confirm-SessionClaim 'account A (the designated test account) on the PRODUCTION Worker'
  $email = Get-Setting 'BW_TEST_EMAIL'
  if (-not $email) { $email = Read-Host -Prompt 'Account A email (the designated test account)' }
  $password = Get-Setting 'BW_TEST_PASSWORD'
  if (-not $password) { $password = Read-Secret 'Account A password' }
  $env:BW_E2E_A_EMAIL = $email
  $env:BW_E2E_A_PASSWORD = $password
  $aUid = Get-Setting 'BW_TEST_USER_ID'
  if ($aUid) { $env:BW_E2E_A_UID = $aUid }

  node (Join-Path $PSScriptRoot 'quotation_media_production_smoke.mjs')
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_E2E_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
