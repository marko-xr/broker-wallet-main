<#
  C3B.7 prepared cleanup — by default OFFLINE verification only.
  -Apply is forbidden without a separate explicit owner approval.
  Use from the same staging-acceptance folder as app_session_claim.mjs.
  No Supabase service-role keys, R2 keys or Cloudflare API credentials.
#>
param([switch] $Apply)
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'toolkit_cleanup_exact9.mjs'
if (-not $Apply) {
  & node $runner --check
  exit $LASTEXITCODE
}

Write-Host 'WARNING: This mode makes hosted calls, CLAIMS both disposable accounts and permanently finalizes EXACTLY NINE test document deletions.'
Write-Host 'DO NOT use -Apply without the owner separately approving live deletion after reviewing the manifest.'
$answer = Read-Host 'Type DELETE EXACT NINE TEST DOCUMENTS to continue'
if ($answer -cne 'DELETE EXACT NINE TEST DOCUMENTS') { throw 'Cancelled before hosted calls.' }

function Read-LocalSecret([string] $prompt) {
  $secure = Read-Host $prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
try {
  # Avoid the earlier stale environment-key error: ask every time.
  $env:BW_C3B7_STAGING_KEY = Read-LocalSecret 'CURRENT staging gate key (hidden)'
  $env:BW_C3B7_A_EMAIL = Read-Host 'Owner-controlled disposable test account A email'
  $env:BW_C3B7_A_PASSWORD = Read-LocalSecret 'Test account A password (hidden)'
  $env:BW_C3B7_B_EMAIL = Read-Host 'Owner-controlled disposable test account B email'
  $env:BW_C3B7_B_PASSWORD = Read-LocalSecret 'Test account B password (hidden)'
  $env:BW_C3B7_APPROVED = '1'
  $env:BW_C3B7_CONFIRM = $answer
  & node $runner --apply
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_C3B7_*' } | ForEach-Object {
    Remove-Item -LiteralPath ("Env:" + $_.Name) -ErrorAction SilentlyContinue
  }
}
exit $code
