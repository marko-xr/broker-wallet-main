<#
  Broker Wallet — Toolkit Cloud Documents real-R2 STAGING acceptance launcher.

  Run by the owner, in the owner's own terminal, against the STAGING Worker only. It takes the staging
  gate key and the two disposable test accounts' credentials from the local environment (falling back to
  masked prompts), gives them to the Node runner for this one run only, and clears its copies afterwards.
  Nothing secret is written to disk or printed.

  Settings read (process scope first, then User scope):
    BW_E2E_STAGING_KEY                         the staging gate key (the same one the other launchers use)
    BW_TOOLKIT_A_EMAIL / BW_TOOLKIT_A_PASSWORD account A: a DISPOSABLE Supabase test account
    BW_TOOLKIT_B_EMAIL / BW_TOOLKIT_B_PASSWORD account B: a second, different DISPOSABLE test account
    BW_TOOLKIT_A_UID / BW_TOOLKIT_B_UID        optional: the runner refuses to continue if the signed-in
                                               account is not this one
  The designated test account used by the other launchers (BW_TEST_*) is deliberately NOT used here: it is
  the account on the owner's phone.

  Phases (-Phases, default A):
    A  basic real-R2 smoke (PDF first; stops on the first failure)
    B  write-once: replay of a signed PUT must be refused by R2
    C  isolation between the two accounts, and (at the end of the run) a superseded session
    D  lifecycle: rename, stale version, idempotent confirm, remove, tombstone, retries
    E  cleanup safety (no write; the sweep is never triggered)
  Examples:  -Phases A     -Phases AB     -Phases ABCDE

  Single Active Device: the run CLAIMS the active app session for each account, which ends every other
  session of that account. The launcher asks you to type CLAIM first. The runner then asks for a SECOND,
  separate confirmation (CREATE TEST DOCUMENTS) before it creates any document or PUTs any byte to R2.

  The run creates only synthetic documents titled "staging-e2e-toolkit-<run>" owned by the two test
  accounts, requests removal of each at the end (final deletion/tombstones may be deferred by the signed-URL window) and never touches anything
  else. The report goes to reports\toolkit_staging_<run>.json (gitignored) and holds no secret, e-mail,
  account id, document id, object key or URL.
#>
param(
  [string] $WorkerUrl = 'https://r2-profile-upload-staging.mohammed-developer-code.workers.dev',
  [string] $Phases = 'A'
)

$ErrorActionPreference = 'Stop'

function Confirm-SessionClaim {
  Write-Host ''
  Write-Host 'This run CLAIMS the active Broker Wallet app session for test account A and test account B (Single Active Device).'
  Write-Host 'Claiming ends every other session of the same account: a phone or emulator signed in to one of them is signed out.'
  Write-Host 'Use two DISPOSABLE test-only accounts, never a real user or the account on your phone.'
  Write-Host 'The run will also ask for a second confirmation before it creates any test document in staging.'
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
  if ($Phases -notmatch '^[A-Ea-e]+$') { throw 'Phases may only contain the letters A, B, C, D, E.' }
  if ($WorkerUrl -notmatch '^https://r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$') {
    throw 'WorkerUrl must be the STAGING Worker (https://r2-profile-upload-staging.<subdomain>.workers.dev). Production is never a target.'
  }
  Confirm-SessionClaim
  $env:BW_E2E_WORKER_URL = $WorkerUrl
  $env:BW_E2E_PHASES = $Phases.ToUpper()
  $env:BW_E2E_STAGING_KEY = Get-OrAsk 'BW_E2E_STAGING_KEY' 'Staging gate key' -Secret
  $env:BW_E2E_A_EMAIL = Get-OrAsk 'BW_TOOLKIT_A_EMAIL' 'Test account A email (disposable)'
  $env:BW_E2E_A_PASSWORD = Get-OrAsk 'BW_TOOLKIT_A_PASSWORD' 'Test account A password' -Secret
  $aUid = Get-Setting 'BW_TOOLKIT_A_UID'
  if ($aUid) { $env:BW_E2E_A_UID = $aUid }
  $env:BW_E2E_B_EMAIL = Get-OrAsk 'BW_TOOLKIT_B_EMAIL' 'Test account B email (a different disposable account)'
  $env:BW_E2E_B_PASSWORD = Get-OrAsk 'BW_TOOLKIT_B_PASSWORD' 'Test account B password' -Secret
  $bUid = Get-Setting 'BW_TOOLKIT_B_UID'
  if ($bUid) { $env:BW_E2E_B_UID = $bUid }

  node (Join-Path $PSScriptRoot 'toolkit_staging_acceptance.mjs')
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_E2E_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
