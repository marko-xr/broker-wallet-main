<#
  Broker Wallet — Quotation private media staging acceptance launcher.

  Run by the owner, in the owner's own terminal, against the STAGING Worker
  only. It takes the staging gate key and the two test accounts' credentials
  from the local environment (falling back to masked prompts), gives them to
  the Node runner for this one run only, and clears its copies afterwards.
  Nothing secret is written to disk or printed.

  Environment it reads (process scope first, then User scope):
    BW_E2E_STAGING_KEY                       the staging gate key
    BW_TEST_EMAIL / BW_TEST_PASSWORD         account A, the designated test-only
                                             account (BW_TEST_USER_ID is checked
                                             by the runner against its uid)
    BW_TEST_B_EMAIL / BW_TEST_B_PASSWORD     account B, a temporary second
                                             account (BW_TEST_B_USER_ID, when set,
                                             is checked against its uid)

  Account A must be the designated test account. Account B must be a different,
  temporary, test-only account; delete it after the run (see README.md).
#>
param(
  [string] $WorkerUrl = 'https://r2-profile-upload-staging.mohammed-developer-code.workers.dev'
)

$ErrorActionPreference = 'Stop'

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
  $env:BW_E2E_WORKER_URL = $WorkerUrl
  $env:BW_E2E_STAGING_KEY = Get-OrAsk 'BW_E2E_STAGING_KEY' 'Staging gate key' -Secret
  $env:BW_E2E_A_EMAIL = Get-OrAsk 'BW_TEST_EMAIL' 'Account A email (the designated test account)'
  $env:BW_E2E_A_PASSWORD = Get-OrAsk 'BW_TEST_PASSWORD' 'Account A password' -Secret
  $aUid = Get-Setting 'BW_TEST_USER_ID'
  if ($aUid) { $env:BW_E2E_A_UID = $aUid }
  $env:BW_E2E_B_EMAIL = Get-OrAsk 'BW_TEST_B_EMAIL' 'Account B email (the temporary second test account)'
  $env:BW_E2E_B_PASSWORD = Get-OrAsk 'BW_TEST_B_PASSWORD' 'Account B password' -Secret
  $bUid = Get-Setting 'BW_TEST_B_USER_ID'
  if ($bUid) { $env:BW_E2E_B_UID = $bUid }

  node (Join-Path $PSScriptRoot 'quotation_media_staging_acceptance.mjs')
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_E2E_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
