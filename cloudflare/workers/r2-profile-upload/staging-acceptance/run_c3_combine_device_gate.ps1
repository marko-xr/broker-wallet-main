<#
  Broker Wallet - Toolkit cloud documents: SAMSUNG acceptance gate (STAGING, DEBUG build).

  Run by the owner, in the owner's own PowerShell, from anywhere (the script finds the repository).
  It builds and starts the CURRENT working-tree source as a DEBUG app pointed at the STAGING Worker for
  Toolkit documents ONLY, and then checks the result from OUTSIDE the app: the Supabase row, and the
  files on the phone. A message in the app is never treated as evidence.

  What it changes
    * Toolkit documents only: --dart-define TOOLKIT_WORKER_URL (the staging Worker) and TOOLKIT_STAGING_KEY.
      It never sets R2_UPLOAD_WORKER_URL, so Profile images, Offer media, plans and account deletion keep
      using the shared (production) address exactly as before.
    * Both defines are honored by a DEBUG build only. A profile or release build ignores them and keeps
      Toolkit documents local. The staging key is a development gate compiled into the debug app; it is not
      a production credential and not an authentication mechanism.

  The key
    Read from BW_E2E_STAGING_KEY (process, then user scope - the same variable the other staging launchers
    use) or typed at a hidden prompt. It is written only to a private temporary file that Flutter reads
    (--dart-define-from-file), deleted in a finally block, and never printed or logged. Do not run flutter
    with -v and do not screen-share this window while the app builds.

  Tools (-Tool): combine_pdfs (default), scanner, image_to_pdf, signature. The phase notes below say
  Combine PDFs; the other three tools restore their documents by themselves when their screen opens, so
  for them RestoreBefore only prints a note and RestoreAfter is the evidence.

  Phases (run in this order; each prints PASS or STOP)
    Check          read-only: source markers, source fingerprint, tools, device, staging address
    Run            build + start the debug app (first run: also creates two disposable PDFs on the phone
                   and a unique document title). Run it again after Uninstall for the reinstall.
    VerifyUpload   BEFORE any uninstall: the Supabase row must be 'ready' in the STAGING bucket, the local
                   file's size and SHA-256 must equal the row, and the phone's journal must say confirmed.
                   Writes a pass marker. If it STOPs, do NOT uninstall: the stage that failed is named.
    Uninstall      refuses without the pass marker; asks you to type UNINSTALL
    RestoreBefore  after reinstall + sign-in + opening Combine PDFs, WITHOUT opening the document: the file
                   must NOT be on the phone yet and the row must still be ready
    RestoreAfter   after opening the document: the file is on the phone and byte-identical (SHA-256) to
                   the one uploaded before the uninstall
    VerifyDelete   optional: after deleting the document in the app, the row is deleted and the file gone
    Reset          forgets the gate state (a new gate starts with a new document title)

  Single Active Device: use the test account only on this phone while the gate runs. The staging
  acceptance runners CLAIM an account's session and sign the phone out.

  Requirements: Flutter, adb (USB debugging on, device authorized), and optionally the Supabase CLI logged
  in as the owner (the script falls back to asking you to run one SELECT in the dashboard SQL editor).
  Nothing here deploys, writes to Supabase or R2, or changes the repository.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Check', 'Run', 'VerifyUpload', 'Uninstall', 'RestoreBefore', 'RestoreAfter', 'VerifyDelete', 'Reset')]
  [string] $Phase,
  [string] $DeviceId = '',
  [string] $ExpectedAccountPrefix = '',
  [ValidateSet('combine_pdfs', 'scanner', 'image_to_pdf', 'signature')]
  [string] $Tool = 'combine_pdfs',
  [string] $WorkerUrl = 'https://r2-profile-upload-staging.mohammed-developer-code.workers.dev',
  [string] $ProjectRef = 'rbvcnvqpdqrhywcgxkne'
)

$ErrorActionPreference = 'Stop'

$Package = 'com.example.broker_wallet'
$StagingBucket = 'broker-wallet-media-staging'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
$ReportsDir = Join-Path $PSScriptRoot 'reports'
$StatePath = Join-Path $ReportsDir 'c3_gate_state.json'
$LogPath = Join-Path $ReportsDir ('c3_combine_gate_{0}.log' -f (Get-Date -Format 'yyyyMMdd'))
# The tool under test (-Tool): its folder on the phone and how its documents are named there.
$ToolFolders = @{ combine_pdfs = 'combine_pdfs'; scanner = 'scanner'; image_to_pdf = 'image_to_pdf'; signature = 'signature_pdfs' }
$ToolNames = @{ combine_pdfs = 'Combine PDFs'; scanner = 'Scanner'; image_to_pdf = 'Images to PDF'; signature = 'Document Signature' }
$ToolFolder = $ToolFolders[$Tool]
$ToolName = $ToolNames[$Tool]
$ScratchDir = Join-Path $ReportsDir 'c3_gate_supabase_scratch'

# The files whose current content the build must contain, and the markers that prove the
# corrected source (not an older checkout) is what will be built.
$FingerprintFiles = @(
  'lib/src/config/r2_config.dart',
  'lib/src/services/toolkit_documents/r2_toolkit_document_service.dart',
  'lib/src/services/toolkit_documents/toolkit_cloud_library.dart',
  'lib/src/services/toolkit_documents/toolkit_cloud_wiring.dart',
  'lib/src/services/toolkit_documents/toolkit_document_models.dart',
  'lib/src/services/toolkit_documents/toolkit_document_upload_coordinator.dart',
  'lib/src/services/toolkit_documents/toolkit_document_sync_journal.dart',
  'lib/src/services/toolkit_documents/toolkit_document_download_service.dart',
  'lib/src/services/combine_pdf/combine_pdf_store.dart',
  'lib/src/services/combine_pdf/combine_wiring.dart',
  'lib/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart',
  'lib/src/views/Screens/home/Toolkit/combine_pdfs_view.dart',
  'lib/src/services/toolkit_documents/toolkit_cloud_sync.dart',
  'lib/src/services/toolkit_documents/toolkit_account_files.dart',
  'lib/src/services/scanner/scanner_document_store.dart',
  'lib/src/services/scanner/scanner_wiring.dart',
  'lib/src/viewmodels/scanner/scanner_viewmodel.dart',
  'lib/src/services/image_to_pdf/image_pdf_store.dart',
  'lib/src/services/image_to_pdf/image_pdf_wiring.dart',
  'lib/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart',
  'lib/src/services/signature/signature_store.dart',
  'lib/src/services/signature/signature_wiring.dart',
  'lib/src/viewmodels/signature/signature_library_viewmodel.dart',
  'lib/src/views/Widgets/toolkit_cloud_status_line.dart'
)
$SourceMarkers = @(
  @{ File = 'lib/src/config/r2_config.dart'; Text = 'TOOLKIT_WORKER_URL' },
  @{ File = 'lib/src/config/r2_config.dart'; Text = 'resolveToolkitStagingKey' },
  @{ File = 'lib/src/services/toolkit_documents/r2_toolkit_document_service.dart'; Text = 'X-Broker-Wallet-Staging-Key' },
  @{ File = 'lib/src/services/toolkit_documents/r2_toolkit_document_service.dart'; Text = 'R2Config.toolkitStagingKey' },
  @{ File = 'lib/src/services/toolkit_documents/toolkit_cloud_library.dart'; Text = 'Future<void> idle()' },
  @{ File = 'lib/src/services/toolkit_documents/toolkit_document_models.dart'; Text = 'enabled && kDebugMode' },
  @{ File = 'lib/src/viewmodels/combine_pdf/combine_pdf_viewmodel.dart'; Text = 'cloud.queue(' },
  @{ File = 'lib/src/services/combine_pdf/combine_wiring.dart'; Text = 'ToolkitCloudWiring.create' },
  @{ File = 'lib/src/services/toolkit_documents/toolkit_cloud_sync.dart'; Text = 'class ToolkitCloudSync' },
  @{ File = 'lib/src/viewmodels/scanner/scanner_viewmodel.dart'; Text = 'ToolkitCloudSync(' },
  @{ File = 'lib/src/viewmodels/image_to_pdf/image_pdf_viewmodel.dart'; Text = 'ToolkitCloudSync(' },
  @{ File = 'lib/src/viewmodels/signature/signature_library_viewmodel.dart'; Text = 'ToolkitCloudSync(' }
)

# What the phone's journal says (ToolkitFailure.name) mapped to the stage that failed.
$FailureHints = @{
  'forbidden'         = 'AUTHORIZE: the Worker answered 403 without a code. The staging gate refused the request: the key is missing or wrong (or was rotated).'
  'routeUnavailable'  = 'AUTHORIZE: the Worker answered 404. Toolkit routes are OFF on that Worker, or the address is wrong (production ships them off).'
  'unauthorized'      = 'AUTHORIZE: 401. The access token was refused (expired, or not this Supabase project).'
  'sessionSuperseded' = 'AUTHORIZE: Single Active Device. Another sign-in or a staging runner took over this account. Sign in again on the phone.'
  'unavailable'       = 'No answer or a 5xx: no route to the Worker, TLS, or a Worker error. With a pending_upload row, the CONFIRM step failed.'
  'interrupted'       = 'A timeout or a cut connection during a request or during the upload (PUT).'
  'uploadRejected'    = 'PUT: R2 refused the signed upload (signature, headers or an expired URL).'
  'uploadIncomplete'  = 'CONFIRM: the Worker could not find the uploaded object. The PUT did not arrive.'
  'typeMismatch'      = 'CONFIRM: the stored bytes are not the declared type (content type or PDF framing).'
  'integrityMismatch' = 'The local file does not match its recorded size or hash. It is not uploaded.'
  'fileUnavailable'   = 'The local file could not be read for the upload.'
  'notConfigured'     = 'No Toolkit Worker address: the build was not started with TOOLKIT_WORKER_URL (use the Run phase).'
  'notSignedIn'       = 'No Supabase session on the phone for this account.'
  'accountChanged'    = 'A different account was signed in while the upload ran.'
  'tooLarge'          = 'The document is over the per-document limit.'
  'storageLimit'      = 'The account is at its cloud storage limit.'
  'documentLimit'     = 'The account is at its cloud document limit.'
  'rateLimited'       = 'Too many requests; the app waits and retries.'
  'tooManyPending'    = 'Too many uploads are waiting for this account; the app waits and retries.'
  'staleDocument'     = 'The document predates the account deletion history; it needs an explicit acknowledgement.'
  'idConflict'        = 'The document id was used for another file, or belongs to someone else.'
}

# --------------------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------------------

function Write-Gate([string] $Level, [string] $Message) {
  $color = switch ($Level) {
    'PASS' { 'Green' }
    'STOP' { 'Red' }
    'WARN' { 'Yellow' }
    'NOTE' { 'Cyan' }
    default { 'Gray' }
  }
  $line = '[{0}] {1}' -f $Level, $Message
  Write-Host $line -ForegroundColor $color
  try {
    if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Force -Path $ReportsDir | Out-Null }
    Add-Content -LiteralPath $LogPath -Value ('{0} {1}' -f (Get-Date).ToUniversalTime().ToString('s'), $line)
  } catch { }
}

function Stop-Gate([string] $Message) {
  Write-Gate 'STOP' $Message
  Write-Gate 'STOP' 'Do NOT uninstall the app or continue to the next phase. Report this output (it holds no secret).'
  exit 2
}

# --------------------------------------------------------------------------------------------------
# State (no secret is ever stored)
# --------------------------------------------------------------------------------------------------

function Get-State {
  if (-not (Test-Path -LiteralPath $StatePath)) { return $null }
  try { return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) } catch { return $null }
}

function Save-State($State) {
  if (-not (Test-Path -LiteralPath $ReportsDir)) { New-Item -ItemType Directory -Force -Path $ReportsDir | Out-Null }
  ($State | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $StatePath -Encoding ascii
}

function Has-Prop($Object, [string] $Name) {
  return ($null -ne $Object) -and ($null -ne $Object.PSObject.Properties[$Name])
}

# --------------------------------------------------------------------------------------------------
# Source: markers and fingerprint
# --------------------------------------------------------------------------------------------------

function Test-SourceMarkers {
  foreach ($marker in $SourceMarkers) {
    $path = Join-Path $RepoRoot $marker.File
    if (-not (Test-Path -LiteralPath $path)) { Stop-Gate ('Source file is missing: {0}' -f $marker.File) }
    $text = [System.IO.File]::ReadAllText($path)
    if (-not $text.Contains($marker.Text)) {
      Stop-Gate ('The corrected source is not on disk: "{0}" was not found in {1}. This is an older checkout; nothing was built.' -f $marker.Text, $marker.File)
    }
  }
  Write-Gate 'PASS' ('All {0} corrected-source markers are present in the working tree.' -f $SourceMarkers.Count)
}

function Get-SourceFingerprint {
  $lines = foreach ($relative in $FingerprintFiles) {
    $path = Join-Path $RepoRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { Stop-Gate ('Source file is missing: {0}' -f $relative) }
    '{0}:{1}' -f $relative, (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower()
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 16) }
  finally { $sha.Dispose() }
}

# --------------------------------------------------------------------------------------------------
# Tools and the phone
# --------------------------------------------------------------------------------------------------

function Find-Adb {
  $command = Get-Command adb -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
    if ($root) {
      $candidate = Join-Path $root 'platform-tools\adb.exe'
      if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
  }
  return $null
}

function Invoke-Native([string] $Exe, [string[]] $Arguments) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { $output = & $Exe @Arguments 2>&1 } finally { $ErrorActionPreference = $previous }
  $code = $LASTEXITCODE
  $text = (($output | ForEach-Object { "$_" }) -join "`n").Trim()
  return [pscustomobject]@{ Code = $code; Text = $text }
}

function Select-Device([switch] $Soft) {
  $adbPath = Find-Adb
  if (-not $adbPath) {
    if ($Soft) { Write-Gate 'WARN' 'adb was not found (PATH, ANDROID_HOME or the default Android SDK folder).'; return }
    Stop-Gate 'adb was not found (PATH, ANDROID_HOME or the default Android SDK folder).'
  }
  $script:Adb = $adbPath
  $listing = Invoke-Native $script:Adb @('devices')
  $ready = @()
  foreach ($line in ($listing.Text -split "`r?`n")) {
    if ($line -match '^(\S+)\s+device$') { $ready += $Matches[1] }
    elseif ($line -match '^(\S+)\s+unauthorized$') { Write-Gate 'WARN' 'A device is connected but unauthorized: accept the USB debugging prompt on the phone.' }
  }
  if ($DeviceId) {
    if ($ready -notcontains $DeviceId) {
      if ($Soft) { Write-Gate 'WARN' ('Device {0} is not connected and authorized.' -f $DeviceId); return }
      Stop-Gate ('Device {0} is not connected and authorized.' -f $DeviceId)
    }
    $script:Device = $DeviceId
  } elseif ($ready.Count -eq 1) {
    $script:Device = $ready[0]
  } elseif ($ready.Count -eq 0) {
    if ($Soft) { Write-Gate 'WARN' 'No authorized Android device is connected.'; return }
    Stop-Gate 'No authorized Android device is connected.'
  } else {
    if ($Soft) { Write-Gate 'WARN' 'More than one device is connected: pass -DeviceId <serial>.'; return }
    Stop-Gate 'More than one device is connected: pass -DeviceId <serial>.'
  }
  $model = Invoke-Native $script:Adb @('-s', $script:Device, 'shell', 'getprop', 'ro.product.model')
  Write-Gate 'PASS' ('Device ready: {0}' -f $model.Text)
}

function Invoke-Adb([string[]] $Arguments) {
  return Invoke-Native $script:Adb (@('-s', $script:Device) + $Arguments)
}

function Test-PackageInstalled {
  $result = Invoke-Adb @('shell', 'pm', 'list', 'packages', $Package)
  return ($result.Text -match ('package:' + [regex]::Escape($Package) + '\s*$')) -or ($result.Text -match ('package:' + [regex]::Escape($Package) + '\r?\n'))
}

# run-as works for a debuggable (debug) build only: that is why this gate is a debug build.
function Invoke-RunAs([string[]] $Arguments) {
  return Invoke-Adb (@('shell', 'run-as', $Package) + $Arguments)
}

function Get-Extension([string] $ContentType) {
  switch ($ContentType) {
    'image/jpeg' { return 'jpg' }
    'image/png' { return 'png' }
    default { return 'pdf' }
  }
}

function Get-RemoteSize([string] $Path) {
  $result = Invoke-RunAs @('stat', '-c', '%s', $Path)
  if ($result.Code -eq 0 -and $result.Text -match '^\d+$') { return [int64]$result.Text }
  return $null
}

function Get-RemoteSha256([string] $Path) {
  $result = Invoke-RunAs @('sha256sum', $Path)
  if ($result.Code -eq 0 -and $result.Text -match '^([0-9a-f]{64})\s') { return $Matches[1] }
  return $null
}

function Get-RemoteText([string] $Path) {
  $result = Invoke-RunAs @('cat', $Path)
  if ($result.Code -eq 0) { return $result.Text }
  return $null
}

function Get-DeviceAccountFolders {
  $result = Invoke-RunAs @('ls', ('app_flutter/' + $ToolFolder))
  if ($result.Code -ne 0) { return @() }
  return @($result.Text -split "`r?`n" | Where-Object { $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' })
}

function Get-TestAccountId {
  $folders = Get-DeviceAccountFolders
  if ($folders.Count -eq 0) {
    Stop-Gate ('The app holds no {0} account folder yet. Sign in and open Toolkit > {0} on the phone first (or the app is not a debug build).' -f $ToolName)
  }
  $matching = @($folders)
  if ($ExpectedAccountPrefix) { $matching = @($folders | Where-Object { $_.StartsWith($ExpectedAccountPrefix.ToLower()) }) }
  if ($matching.Count -ne 1) {
    Stop-Gate ('Expected exactly one account folder on the phone{0}; found {1}. Pass -ExpectedAccountPrefix <first 8 characters of the test account id>.' -f $(if ($ExpectedAccountPrefix) { ' matching the prefix' } else { '' }), $matching.Count)
  }
  $account = $matching[0]
  if (-not $ExpectedAccountPrefix) {
    $answer = Read-Host ('The phone holds {1} documents for the account ending ...{0}. Type YES if that is the authorized test account' -f $account.Substring($account.Length - 6), $ToolName)
    if ($answer -cne 'YES') { Stop-Gate 'The account was not confirmed as the authorized test account.' }
  }
  return $account
}

# --------------------------------------------------------------------------------------------------
# The Supabase row, read independently of the app (SELECT only)
# --------------------------------------------------------------------------------------------------

function Initialize-SupabaseScratch {
  $cli = Get-Command supabase -ErrorAction SilentlyContinue
  if (-not $cli) { return $false }
  $configPath = Join-Path $ScratchDir 'supabase\config.toml'
  if (-not (Test-Path -LiteralPath $configPath)) {
    New-Item -ItemType Directory -Force -Path $ScratchDir | Out-Null
    Push-Location $ScratchDir
    try { cmd /c 'supabase init --force <NUL >NUL 2>&1' | Out-Null } finally { Pop-Location }
    if (-not (Test-Path -LiteralPath $configPath)) {
      New-Item -ItemType Directory -Force -Path (Join-Path $ScratchDir 'supabase') | Out-Null
      Set-Content -LiteralPath $configPath -Value 'project_id = "bw-c3-gate"' -Encoding ascii
    }
  }
  $refPath = Join-Path $ScratchDir 'supabase\.temp\project-ref'
  $linked = (Test-Path -LiteralPath $refPath) -and ((Get-Content -LiteralPath $refPath -Raw).Trim() -eq $ProjectRef)
  if (-not $linked) {
    Push-Location $ScratchDir
    try { $null = Invoke-Native $cli.Source @('link', '--project-ref', $ProjectRef) } finally { Pop-Location }
    $linked = (Test-Path -LiteralPath $refPath) -and ((Get-Content -LiteralPath $refPath -Raw).Trim() -eq $ProjectRef)
  }
  return $linked
}

# Returns an object whose Rows property holds the rows (objects of strings), or $null when the
# CLI could not answer. The rows travel inside an object because PowerShell unrolls an empty
# array returned from a function, which would make "no rows" look like "no answer".
function Invoke-SupabaseSelect([string] $Sql) {
  if (-not (Initialize-SupabaseScratch)) { return $null }
  $cli = Get-Command supabase
  $file = Join-Path $ScratchDir ('q_{0}.sql' -f ([guid]::NewGuid().ToString('N')))
  Set-Content -LiteralPath $file -Value $Sql -Encoding ascii
  Push-Location $ScratchDir
  try { $result = Invoke-Native $cli.Source @('db', 'query', '--linked', '--output-format', 'json', '-f', $file) }
  finally { Pop-Location; Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
  $first = $result.Text.IndexOf('{')
  $last = $result.Text.LastIndexOf('}')
  if ($first -lt 0 -or $last -le $first) { return $null }
  try { $parsed = $result.Text.Substring($first, $last - $first + 1) | ConvertFrom-Json } catch { return $null }
  if (-not (Has-Prop $parsed 'rows')) { return $null }
  return [pscustomobject]@{ Rows = @($parsed.rows) }
}

function Get-DocumentSql([string] $AccountId, [string] $TitlePrefix) {
  if ($AccountId -notmatch '^[0-9a-f-]{36}$') { Stop-Gate 'Internal: the account id is not a UUID.' }
  if ($TitlePrefix -notmatch '^BW-C3-GATE-[0-9]{8}-[0-9]{6}$') { Stop-Gate 'Internal: the gate title is malformed.' }
  return ("select d.id::text as id, d.status::text as status, d.document_type::text as document_type, " +
    "d.content_type::text as content_type, d.size_bytes::text as size_bytes, coalesce(d.page_count::text, '') as page_count, " +
    "d.content_sha256::text as content_sha256, d.bucket::text as bucket, d.upload_attempts::text as upload_attempts, " +
    "to_char(d.created_at at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS') as created_at_utc, " +
    "coalesce(to_char(d.confirmed_at at time zone 'utc', 'YYYY-MM-DD HH24:MI:SS'), '') as confirmed_at_utc, d.title::text as title " +
    "from public.toolkit_documents d where d.owner_id = '" + $AccountId + "'::uuid and d.document_type = '" + $Tool + "' " +
    "and d.title like '" + $TitlePrefix + "%' order by d.created_at desc limit 5;")
}

# The rows for the gate's document, through the CLI or typed in from the dashboard. Returns an
# object whose Rows property is the array (see Invoke-SupabaseSelect).
function Get-DocumentRows([string] $AccountId, [string] $TitlePrefix) {
  $sql = Get-DocumentSql $AccountId $TitlePrefix
  $answer = Invoke-SupabaseSelect $sql
  if ($null -ne $answer) {
    Write-Gate 'INFO' 'Read from Supabase through the CLI (SELECT only).'
    return $answer
  }
  Write-Gate 'WARN' 'The Supabase CLI could not answer. Run this ONE SELECT in the Supabase dashboard SQL editor of the broker-wallet project, then type what it shows:'
  Write-Host $sql
  $count = Read-Host 'How many rows did it return (0-5)'
  if ($count -notmatch '^[0-5]$') { Stop-Gate 'Not a row count.' }
  $typed = @()
  for ($i = 1; $i -le [int]$count; $i++) {
    Write-Host ('Row {0}:' -f $i)
    $typed += [pscustomobject]@{
      id = (Read-Host '  id (full uuid)')
      status = (Read-Host '  status')
      document_type = $Tool
      content_type = (Read-Host '  content_type')
      size_bytes = (Read-Host '  size_bytes')
      page_count = (Read-Host '  page_count')
      content_sha256 = (Read-Host '  content_sha256')
      bucket = (Read-Host '  bucket')
      upload_attempts = (Read-Host '  upload_attempts')
      created_at_utc = ''
      confirmed_at_utc = (Read-Host '  confirmed_at_utc (blank if empty)')
      title = $TitlePrefix
    }
  }
  return [pscustomobject]@{ Rows = $typed }
}

function Write-RowTable($Rows) {
  foreach ($row in $Rows) {
    $idTail = if ($row.id.Length -ge 6) { $row.id.Substring($row.id.Length - 6) } else { $row.id }
    $shaHead = if ($row.content_sha256.Length -ge 8) { $row.content_sha256.Substring(0, 8) } else { $row.content_sha256 }
    Write-Gate 'INFO' ('row ...{0}: status={1} type={2} content={3} size={4} pages={5} sha256={6}.. attempts={7} bucket={8} created={9} confirmed={10}' -f
      $idTail, $row.status, $row.document_type, $row.content_type, $row.size_bytes, $row.page_count, $shaHead, $row.upload_attempts, $row.bucket, $row.created_at_utc, $row.confirmed_at_utc)
  }
}

# --------------------------------------------------------------------------------------------------
# The phone's journal (fixed categories only: state, attempts, failure, confirmed or not)
# --------------------------------------------------------------------------------------------------

function Get-JournalEntries([string] $AccountId) {
  $text = Get-RemoteText ('app_flutter/{1}/{0}/cloud/toolkit_sync_{0}.json' -f $AccountId, $ToolFolder)
  if (-not $text) { return @() }
  try { $parsed = $text | ConvertFrom-Json } catch { return @() }
  if (-not (Has-Prop $parsed 'entries')) { return @() }
  return @($parsed.entries)
}

function Write-JournalEntry($Entry) {
  $idTail = $Entry.documentId.Substring($Entry.documentId.Length - 6)
  $confirmed = if ($Entry.cloudConfirmedAt) { 'yes' } else { 'no' }
  $failure = if ($Entry.lastFailure) { [string]$Entry.lastFailure } else { '-' }
  Write-Gate 'INFO' ('phone journal ...{0}: state={1} attempts={2} lastFailure={3} confirmedByServer={4} deleteRequested={5}' -f $idTail, $Entry.state, $Entry.attempts, $failure, $confirmed, $Entry.deleteRequested)
  if ($Entry.lastFailure -and $FailureHints.ContainsKey([string]$Entry.lastFailure)) {
    Write-Gate 'NOTE' ('  meaning: {0}' -f $FailureHints[[string]$Entry.lastFailure])
  }
}

# --------------------------------------------------------------------------------------------------
# A disposable PDF (valid cross-reference table, ASCII only)
# --------------------------------------------------------------------------------------------------

function New-GatePdfBytes([string] $Label) {
  $stream = 'BT /F1 18 Tf 20 100 Td (' + $Label + ') Tj ET'
  $objects = @(
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    ('<< /Length ' + $stream.Length + " >>`nstream`n" + $stream + "`nendstream"),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'
  )
  $builder = New-Object System.Text.StringBuilder
  [void]$builder.Append("%PDF-1.4`n")
  $offsets = @()
  for ($i = 0; $i -lt $objects.Count; $i++) {
    $offsets += $builder.Length
    [void]$builder.Append((($i + 1).ToString() + " 0 obj`n" + $objects[$i] + "`nendobj`n"))
  }
  $xref = $builder.Length
  [void]$builder.Append("xref`n0 " + ($objects.Count + 1) + "`n")
  [void]$builder.Append("0000000000 65535 f `n")
  foreach ($offset in $offsets) { [void]$builder.Append(($offset.ToString('D10') + " 00000 n `n")) }
  [void]$builder.Append("trailer`n<< /Size " + ($objects.Count + 1) + " /Root 1 0 R >>`nstartxref`n" + $xref + "`n%%EOF`n")
  return [System.Text.Encoding]::ASCII.GetBytes($builder.ToString())
}

# --------------------------------------------------------------------------------------------------
# Secrets: the key lives only in a private temporary file Flutter reads
# --------------------------------------------------------------------------------------------------

function Get-Setting([string] $Name) {
  $value = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $value) { $value = [Environment]::GetEnvironmentVariable($Name, 'User') }
  return $value
}

function Read-Secret([string] $Prompt) {
  $secure = Read-Host -Prompt $Prompt -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

function New-PrivateFile([string] $Path) {
  New-Item -ItemType File -Force -Path $Path | Out-Null
  try {
    $acl = Get-Acl -LiteralPath $Path
    $acl.SetAccessRuleProtection($true, $false)
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule([System.Security.Principal.WindowsIdentity]::GetCurrent().Name, 'FullControl', 'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl
  } catch {
    Write-Gate 'WARN' 'Could not restrict the temporary defines file to this user; it is deleted when the run ends.'
  }
}

# --------------------------------------------------------------------------------------------------
# Common checks
# --------------------------------------------------------------------------------------------------

function Test-WorkerUrl {
  if ($WorkerUrl -notmatch '^https://r2-profile-upload-staging\.[a-z0-9-]+\.workers\.dev$') {
    Stop-Gate 'WorkerUrl must be the STAGING Worker (https://r2-profile-upload-staging.<subdomain>.workers.dev). Production is never a target.'
  }
  Write-Gate 'PASS' ('Toolkit will use the STAGING Worker host: {0}' -f ([uri]$WorkerUrl).Host)
  Write-Gate 'NOTE' 'Profile images, Offer media, plans and account deletion keep the shared address (R2_UPLOAD_WORKER_URL is not set by this script).'
}

function Test-Tools {
  $flutter = Get-Command flutter -ErrorAction SilentlyContinue
  if (-not $flutter) { Stop-Gate 'flutter was not found on PATH.' }
  Write-Gate 'PASS' 'flutter found.'
  $cli = Get-Command supabase -ErrorAction SilentlyContinue
  if ($cli) { Write-Gate 'PASS' 'Supabase CLI found (read-only checks will use it).' }
  else { Write-Gate 'WARN' 'Supabase CLI not found: the checks will ask you to run one SELECT in the dashboard SQL editor.' }
}

function Show-Fingerprint {
  $fingerprint = Get-SourceFingerprint
  if (Get-Command git -ErrorAction SilentlyContinue) {
    $head = Invoke-Native 'git' @('-C', $RepoRoot, 'rev-parse', '--short', 'HEAD')
    $changed = Invoke-Native 'git' @('-C', $RepoRoot, 'status', '--short')
    $count = @($changed.Text -split "`r?`n" | Where-Object { $_ }).Count
    Write-Gate 'INFO' ('Source fingerprint (C3 files, working tree): {0}; git HEAD {1} with {2} changed or untracked paths (a working-tree build, not a commit).' -f $fingerprint, $head.Text, $count)
  } else {
    Write-Gate 'INFO' ('Source fingerprint (C3 files, working tree): {0}' -f $fingerprint)
  }
  return $fingerprint
}

# --------------------------------------------------------------------------------------------------
# Phases
# --------------------------------------------------------------------------------------------------

function Invoke-Check {
  Write-Gate 'INFO' ('Repository: {0}' -f $RepoRoot)
  Test-SourceMarkers
  $null = Show-Fingerprint
  Test-Tools
  Test-WorkerUrl
  $key = Get-Setting 'BW_E2E_STAGING_KEY'
  if ($key) { Write-Gate 'PASS' 'BW_E2E_STAGING_KEY is set (value not shown).' }
  else { Write-Gate 'NOTE' 'BW_E2E_STAGING_KEY is not set: the Run phase will ask for it at a hidden prompt.' }
  Select-Device -Soft
  Write-Gate 'PASS' 'Check finished. Nothing was built, installed or changed.'
}

function Invoke-Run {
  Test-SourceMarkers
  $fingerprint = Show-Fingerprint
  Test-Tools
  Test-WorkerUrl
  Select-Device
  $state = Get-State
  $isReinstall = (Has-Prop $state 'upload') -and ($null -ne $state.upload)

  if (-not $isReinstall) {
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $title = 'BW-C3-GATE-' + $runId
    # Combine PDFs needs two PDFs and Document Signature one; Scanner and Images to PDF
    # make their own document from the camera or a photo, so no file is copied for them.
    $names = @()
    if ($Tool -eq 'combine_pdfs') { $names = @(('bw_c3_gate_a_' + $runId + '.pdf'), ('bw_c3_gate_b_' + $runId + '.pdf')) }
    elseif ($Tool -eq 'signature') { $names = @(('bw_c3_gate_a_' + $runId + '.pdf')) }
    if ($names.Count -gt 0) {
      $localDir = Join-Path $ReportsDir 'c3_gate_pdfs'
      New-Item -ItemType Directory -Force -Path $localDir | Out-Null
      $letter = 'A'
      foreach ($name in $names) {
        [System.IO.File]::WriteAllBytes((Join-Path $localDir $name), (New-GatePdfBytes ('BW C3 GATE ' + $letter + ' ' + $runId)))
        $push = Invoke-Adb @('push', (Join-Path $localDir $name), ('/sdcard/Download/' + $name))
        if ($push.Code -ne 0) { Stop-Gate ('Could not copy {0} to the phone: {1}' -f $name, $push.Text) }
        $letter = [string][char]([int][char]$letter + 1)
      }
      Write-Gate 'PASS' ('Disposable PDF(s) are in the phone''s Download folder: {0}' -f ($names -join ', '))
    }
    $state = [pscustomobject]@{
      version = 1
      runId = $runId
      title = $title
      tool = $Tool
      pdfs = $names
      firstFingerprint = $fingerprint
      startedUtc = (Get-Date).ToUniversalTime().ToString('s')
    }
    Save-State $state
  } else {
    if ($state.firstFingerprint -ne $fingerprint) {
      Write-Gate 'WARN' 'The source changed since the build that uploaded the document. The restore result applies to THIS newer source; the upload result applied to the earlier one.'
    }
    Write-Gate 'NOTE' 'Reinstall run: the pass marker from the upload check is kept.'
  }

  $key = Get-Setting 'BW_E2E_STAGING_KEY'
  if (-not $key) { $key = Read-Secret 'Staging gate key (input hidden)' }
  if (-not $key) { Stop-Gate 'No staging gate key was given.' }

  $definesPath = Join-Path ([System.IO.Path]::GetTempPath()) ('bw_c3_{0}.json' -f ([guid]::NewGuid().ToString('N')))
  New-PrivateFile $definesPath
  $defines = [ordered]@{
    TOOLKIT_CLOUD_DOCUMENTS = 'true'
    TOOLKIT_WORKER_URL = $WorkerUrl
    TOOLKIT_STAGING_KEY = $key
  }
  if ($defines.Contains('R2_UPLOAD_WORKER_URL')) { Stop-Gate 'Internal: the shared media address must not be set.' }
  [System.IO.File]::WriteAllText($definesPath, ($defines | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))

  if ($isReinstall) {
    if ($Tool -eq 'combine_pdfs') {
      Write-Gate 'NOTE' 'In the app: sign in with the test account, open Toolkit > Combine PDFs. The document should be listed as "In your account, not on this phone yet". Do NOT open it. Then run -Phase RestoreBefore in a second terminal.'
    } else {
      Write-Gate 'NOTE' ('In the app: sign in with the test account and open Toolkit > {0}. The document is restored automatically (watch the status line: "Restoring your documents...") and then listed. Then run -Phase RestoreAfter in a second terminal.' -f $ToolName)
    }
  } else {
    switch ($Tool) {
      'combine_pdfs' { Write-Gate 'NOTE' ('In the app: sign in with the authorized test account, open Toolkit > Combine PDFs, pick the two files named {0} and {1} from Downloads, name the result EXACTLY: {2}, then Combine.' -f $state.pdfs[0], $state.pdfs[1], $state.title) }
      'signature' { Write-Gate 'NOTE' ('In the app: sign in with the authorized test account, open Toolkit > Document Signature, pick the file named {0} from Downloads, add a signature or text, and save it with the name EXACTLY: {1}.' -f $state.pdfs[0], $state.title) }
      'scanner' { Write-Gate 'NOTE' ('In the app: sign in with the authorized test account, open Toolkit > Scanner, scan any page as a PDF, and save it with the name EXACTLY: {0}.' -f $state.title) }
      'image_to_pdf' { Write-Gate 'NOTE' ('In the app: sign in with the authorized test account, open Toolkit > Images to PDF, pick or take one picture, convert, and save it with the name EXACTLY: {0}.' -f $state.title) }
    }
    Write-Gate 'NOTE' 'Wait for the status line to say "All documents are saved to your account". That message is NOT the evidence: in a SECOND terminal run -Phase VerifyUpload. Do not uninstall before it prints PASS.'
  }
  Write-Gate 'NOTE' 'Starting the debug build from the current source. Do not use flutter -v and do not share this window.'

  $code = 1
  Push-Location $RepoRoot
  try {
    & flutter run -d $script:Device ('--dart-define-from-file=' + $definesPath)
    $code = $LASTEXITCODE
  } finally {
    Pop-Location
    Remove-Item -LiteralPath $definesPath -Force -ErrorAction SilentlyContinue
    $key = $null
    $defines = $null
  }
  Write-Gate 'INFO' ('flutter run ended with exit code {0}. The temporary defines file was deleted.' -f $code)
}

function Invoke-VerifyUpload {
  $state = Get-State
  if ($null -eq $state) { Stop-Gate 'No gate state. Run -Phase Run first.' }
  Select-Device
  if (-not (Test-PackageInstalled)) { Stop-Gate 'The app is not installed on the phone.' }
  $account = Get-TestAccountId
  Write-Gate 'INFO' ('Account folder on the phone: ...{0}' -f $account.Substring($account.Length - 6))

  $fingerprint = Get-SourceFingerprint
  if ($fingerprint -ne $state.firstFingerprint) {
    Write-Gate 'WARN' 'The source changed after the build you tested; this result applies to the build, not to the files now on disk.'
  } else {
    Write-Gate 'PASS' 'The source on disk is unchanged since this gate started its build.'
  }

  $journal = @(Get-JournalEntries $account | Where-Object { $_.title -like ($state.title + '*') })
  $rows = @((Get-DocumentRows $account $state.title).Rows)
  Write-RowTable $rows

  if ($rows.Count -eq 0) {
    foreach ($entry in $journal) { Write-JournalEntry $entry }
    if ($journal.Count -eq 0) {
      Stop-Gate 'STAGE 0 - no document of this name exists on the phone or in Supabase: the Combine save did not happen, or its name was not exactly the gate title.'
    }
    Stop-Gate 'STAGE 1 - AUTHORIZE: the phone holds the document but Supabase has NO record of it, so the Worker never created one. See the meaning lines above.'
  }
  $row = $rows[0]
  foreach ($entry in $journal) { Write-JournalEntry $entry }
  if ($row.status -ne 'ready') {
    Stop-Gate ('STAGE 2/3 - PUT or CONFIRM: the record exists but its status is "{0}", not "ready". The bytes are not confirmed in the cloud. See the meaning lines above. (If the app still says "Backing up", give it a minute and run this phase again; it is a failure only once the app has stopped working on it.)' -f $row.status)
  }
  if ($row.bucket -ne $StagingBucket) { Stop-Gate ('The record is in the bucket "{0}", not the staging bucket. The wrong Worker was used.' -f $row.bucket) }
  if ($row.content_type -ne 'application/pdf') { Stop-Gate 'The record is not a PDF.' }
  if (-not $row.confirmed_at_utc) { Stop-Gate 'The record is ready but has no confirmation time.' }
  Write-Gate 'PASS' 'GATE 1 - Supabase says the document is READY in the STAGING bucket (read independently of the app).'

  $localPath = 'app_flutter/{2}/{0}/files/{1}.{3}' -f $account, $row.id, $ToolFolder, (Get-Extension $row.content_type)
  $size = Get-RemoteSize $localPath
  if ($null -eq $size) { Stop-Gate 'The document file is not on the phone (or run-as is unavailable: this must be a debug build).' }
  if ([string]$size -ne $row.size_bytes) { Stop-Gate ('The phone''s file is {0} bytes but the record says {1}.' -f $size, $row.size_bytes) }
  $sha = Get-RemoteSha256 $localPath
  if ($sha -ne $row.content_sha256) { Stop-Gate 'The SHA-256 of the phone''s file does not equal the record''s digest.' }
  Write-Gate 'PASS' 'GATE 2 - the file on the phone has the size and SHA-256 recorded in the cloud.'

  $entry = $journal | Where-Object { $_.documentId -eq $row.id } | Select-Object -First 1
  if ($null -eq $entry -or $entry.state -ne 'savedToCloud' -or -not $entry.cloudConfirmedAt) {
    Stop-Gate 'The phone''s journal does not say the server confirmed this document.'
  }
  Write-Gate 'PASS' 'GATE 3 - the phone''s journal records the server''s confirmation.'

  if (Has-Prop $state 'upload') { $state.PSObject.Properties.Remove('upload') }
  $marker = [pscustomobject]@{
    documentId = $row.id
    sha256 = $row.content_sha256
    sizeBytes = [int64]$row.size_bytes
    extension = (Get-Extension $row.content_type)
    tool = $Tool
    bucket = $row.bucket
    verifiedUtc = (Get-Date).ToUniversalTime().ToString('s')
  }
  $state | Add-Member -NotePropertyName upload -NotePropertyValue $marker
  Save-State $state
  Write-Gate 'PASS' 'UPLOAD VERIFIED. The remote record is ready and its bytes equal the phone''s file. Only now may you run -Phase Uninstall.'
  Write-Gate 'NOTE' 'This proves the upload. It does NOT yet prove the document survives a reinstall: that needs the Restore phases.'
}

function Invoke-Uninstall {
  $state = Get-State
  if ($null -eq $state -or -not (Has-Prop $state 'upload')) {
    Stop-Gate 'Refusing to uninstall: no VerifyUpload PASS marker exists. The upload has not been proven.'
  }
  Select-Device
  if (-not (Test-PackageInstalled)) { Stop-Gate 'The app is not installed on the phone.' }
  Write-Gate 'NOTE' 'This removes the app and its private files from the phone. The document survives only if the cloud copy is real, which VerifyUpload just proved.'
  $answer = Read-Host 'Type UNINSTALL to continue'
  if ($answer -cne 'UNINSTALL') { Stop-Gate 'Cancelled. Nothing was removed.' }
  $result = Invoke-Adb @('uninstall', $Package)
  if ($result.Code -ne 0 -or $result.Text -notmatch 'Success') { Stop-Gate ('adb uninstall did not succeed: {0}' -f $result.Text) }
  Write-Gate 'PASS' 'The app was uninstalled. Run -Phase Run again to reinstall it from the same source, sign in, and open Combine PDFs.'
}

function Get-UploadMarker {
  $state = Get-State
  if ($null -eq $state -or -not (Has-Prop $state 'upload')) { Stop-Gate 'No upload PASS marker: run VerifyUpload first.' }
  if ((Has-Prop $state 'tool') -and $state.tool -ne $Tool) {
    Stop-Gate ('The upload marker belongs to the tool "{0}" but this run says -Tool {1}. Use the same -Tool for every phase of one gate (or -Phase Reset to start another).' -f $state.tool, $Tool)
  }
  return $state
}

function Test-RowStillReady($State, [string] $Account) {
  $rows = @((Get-DocumentRows $Account $State.title).Rows)
  Write-RowTable $rows
  $row = $rows | Where-Object { $_.id -eq $State.upload.documentId } | Select-Object -First 1
  if ($null -eq $row) { Stop-Gate 'The cloud record of the uploaded document is gone.' }
  if ($row.status -ne 'ready') { Stop-Gate ('The cloud record is "{0}", not ready.' -f $row.status) }
  if ($row.content_sha256 -ne $State.upload.sha256) { Stop-Gate 'The cloud record''s digest changed.' }
  return $row
}

function Invoke-RestoreBefore {
  if ($Tool -ne 'combine_pdfs') {
    Write-Gate 'NOTE' ('{0} restores its documents automatically when it opens, so there is no "not on the phone yet" moment to check. The evidence is -Phase RestoreAfter: after the uninstall, the file on the phone must equal the uploaded one byte for byte.' -f $ToolName)
    return
  }
  $state = Get-UploadMarker
  Select-Device
  if (-not (Test-PackageInstalled)) { Stop-Gate 'The app is not installed. Run -Phase Run to reinstall it.' }
  $account = Get-TestAccountId
  $null = Test-RowStillReady $state $account
  $id = $state.upload.documentId
  $filePath = 'app_flutter/{2}/{0}/files/{1}.{3}' -f $account, $id, $ToolFolder, $state.upload.extension
  $restorePath = 'app_flutter/{2}/{0}/restore/{1}.{3}' -f $account, $id, $ToolFolder, $state.upload.extension
  if ($null -ne (Get-RemoteSize $filePath)) { Stop-Gate 'The file is ALREADY on the phone. This is not a clean reinstall (or the document was already opened). The restore cannot be proven from here.' }
  if ($null -ne (Get-RemoteSize $restorePath)) { Stop-Gate 'A download is already in the restore folder; this is not a clean starting point.' }
  Write-Gate 'PASS' 'RESTORE-BEFORE - the cloud record is still ready and the file is NOT on this phone yet. Now open the document in Combine PDFs (it downloads), then run -Phase RestoreAfter.'
}

function Invoke-RestoreAfter {
  $state = Get-UploadMarker
  Select-Device
  $account = Get-TestAccountId
  $row = Test-RowStillReady $state $account
  $id = $state.upload.documentId
  $filePath = 'app_flutter/{2}/{0}/files/{1}.{3}' -f $account, $id, $ToolFolder, $state.upload.extension
  $size = Get-RemoteSize $filePath
  if ($null -eq $size) { Stop-Gate 'The file is still not on the phone: the download did not complete. Open the document in the app; if it fails, send the app''s message (no secret).' }
  if ([string]$size -ne [string]$state.upload.sizeBytes) { Stop-Gate ('The restored file is {0} bytes; the uploaded file was {1}.' -f $size, $state.upload.sizeBytes) }
  $sha = Get-RemoteSha256 $filePath
  if ($sha -ne $state.upload.sha256) { Stop-Gate 'The restored file''s SHA-256 differs from the file uploaded before the uninstall.' }
  Write-Gate 'PASS' 'RESTORE VERIFIED. After a real uninstall and reinstall, the document came back from the cloud byte-for-byte (same size, same SHA-256 as before the uninstall).'
  Write-Gate 'NOTE' ('Now {0} has passed the full device gate. Keep this log. A tool is covered only by its own run: repeat the phases with -Tool for each of the others.' -f $ToolName)
}

function Invoke-VerifyDelete {
  $state = Get-UploadMarker
  Select-Device
  $account = Get-TestAccountId
  $rows = @((Get-DocumentRows $account $state.title).Rows)
  Write-RowTable $rows
  $row = $rows | Where-Object { $_.id -eq $state.upload.documentId } | Select-Object -First 1
  if ($null -eq $row) { Stop-Gate 'The record is gone entirely (a tombstone should remain).' }
  if ($row.status -ne 'deleted' -and $row.status -ne 'pending_delete') { Stop-Gate ('The record is "{0}": the delete did not reach the cloud.' -f $row.status) }
  $filePath = 'app_flutter/{2}/{0}/files/{1}.{3}' -f $account, $state.upload.documentId, $ToolFolder, $state.upload.extension
  if ($null -ne (Get-RemoteSize $filePath)) { Stop-Gate 'The cloud says deleted but the phone still holds the file.' }
  if ($row.status -eq 'pending_delete') { Write-Gate 'WARN' 'The record is pending_delete: the removal is recorded but the object cleanup is not finished yet.' }
  Write-Gate 'PASS' ('DELETE VERIFIED. The cloud record is "{0}" and the phone no longer holds the file.' -f $row.status)
}

function Invoke-Reset {
  if (Test-Path -LiteralPath $StatePath) { Remove-Item -LiteralPath $StatePath -Force }
  Write-Gate 'PASS' 'Gate state cleared. The next Run creates a new document title.'
}

# --------------------------------------------------------------------------------------------------

try {
  switch ($Phase) {
    'Check' { Invoke-Check }
    'Run' { Invoke-Run }
    'VerifyUpload' { Invoke-VerifyUpload }
    'Uninstall' { Invoke-Uninstall }
    'RestoreBefore' { Invoke-RestoreBefore }
    'RestoreAfter' { Invoke-RestoreAfter }
    'VerifyDelete' { Invoke-VerifyDelete }
    'Reset' { Invoke-Reset }
  }
} catch {
  Write-Gate 'STOP' ('Unexpected error in phase {0}: {1}' -f $Phase, $_.Exception.Message)
  Write-Gate 'STOP' 'Nothing is proven. Do not uninstall. Report this line.'
  exit 3
}
