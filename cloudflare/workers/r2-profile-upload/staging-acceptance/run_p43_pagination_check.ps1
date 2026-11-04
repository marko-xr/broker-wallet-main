<#
  Broker Wallet — P4.3b hosted pagination check launcher (owner-run only).

  Run in your OWN terminal. The hosted project is PRODUCTION (staging shares it).
  Use the DEDICATED test account (for example the disposable account B of the
  staging runners) — never account A, the account on your phone.

  It asks for the test account's email, password (masked) and user id here, at
  your keyboard. Nothing is read from BW_TEST_* (those are account A's), nothing
  is passed on a command line, written to disk or printed. The values live in
  this process's environment for this one run and are removed afterwards.

  The Node runner then asks you to type each state-changing step yourself:
    SIGN IN   one sign-in (creates one Auth session; no retry on failure)
    CLAIM     claim the active app session (ends the test account's other sessions)
    DISPLACE  only if you choose the displacement step: a second sign-in + claim
  After any sign-in it releases the claim and signs its sessions out
  (scope=local). It never creates, changes or deletes app data. The report
  (counts and PASS/FAIL only) goes to reports\p43_pagination_<time>.json.

  Dry run with no network:  node .\p43_pagination_hosted_check.mjs plan
#>
$ErrorActionPreference = 'Stop'

function Read-Secret([string] $Prompt) {
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

$code = 1
try {
  Write-Host ''
  Write-Host 'P4.3b pagination check on the PRODUCTION Supabase project, as the dedicated test account.'
  Write-Host 'Never account A (the phone account). Every state-changing step asks you to type it.'
  Write-Host ''
  $email = (Read-Host -Prompt 'Dedicated test account email').Trim()
  $accountAEmail = [Environment]::GetEnvironmentVariable('BW_TEST_EMAIL', 'User')
  if ($accountAEmail -and ($email -ieq $accountAEmail.Trim())) {
    throw 'Refused: that is account A (BW_TEST_EMAIL). Use the dedicated test account. Nothing was sent.'
  }
  $uid = (Read-Host -Prompt 'Dedicated test account user id (uuid)').Trim().ToLowerInvariant()
  $password = Read-Secret 'Dedicated test account password'
  $displace = Read-Host -Prompt 'Also run the displacement step (second sign-in + claim)? Type y for yes'

  $env:BW_P43_EMAIL = $email
  $env:BW_P43_PASSWORD = $password
  $env:BW_P43_TEST_USER_ID = $uid
  if ($displace -ceq 'y') { $env:BW_P43_DISPLACEMENT = '1' }
  $password = $null

  node (Join-Path $PSScriptRoot 'p43_pagination_hosted_check.mjs') run
  $code = $LASTEXITCODE
}
finally {
  Get-ChildItem Env: | Where-Object { $_.Name -like 'BW_P43_*' } | ForEach-Object { Remove-Item -LiteralPath ("Env:" + $_.Name) }
}
exit $code
