<#
  Termius localization auto-updater.

  Detects when the locally installed Termius version changed (auto-update),
  then downloads the latest localized app.asar from
  https://github.com/ArcSurge/Termius-Pro-zh_CN and replaces
  %LOCALAPPDATA%\Programs\Termius\resources\app.asar with it.

  Also re-applies when a newer localization pack (not newer than the
  installed Termius) becomes available on GitHub.

  Intended to be run by a scheduled task every 30 minutes.
  Each run is a cheap no-op unless one of the conditions above is met.
  Run with -Force to apply immediately regardless of state.
#>
param([switch]$Force)

$ErrorActionPreference = 'Stop'

$WorkDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogFile   = Join-Path $WorkDir 'update-log.txt'
$StateFile = Join-Path $WorkDir 'state.json'
$AsarName  = 'app-windows-localize.asar'
$AsarPath  = Join-Path $WorkDir $AsarName

$TermiusDir = Join-Path $env:LOCALAPPDATA 'Programs\Termius'
$ExePath    = Join-Path $TermiusDir 'Termius.exe'
$AppAsar    = Join-Path $TermiusDir 'resources\app.asar'
$BackupDir  = Join-Path $WorkDir 'backup'

$RepoOwner = 'ArcSurge'
$RepoName  = 'Termius-Pro-zh_CN'
$FeedUrl   = "https://github.com/$RepoOwner/$RepoName/releases.atom"
$DlUrl     = "https://github.com/$RepoOwner/$RepoName/releases/latest/download/$AsarName"

function Write-Log([string]$Message) {
    $Line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
}

function Get-InstalledVersion {
    if (-not (Test-Path -LiteralPath $ExePath)) { return $null }
    return (Get-Item -LiteralPath $ExePath).VersionInfo.FileVersion
}

function Get-LatestPackVersion {
    try {
        $Resp = Invoke-WebRequest -Uri $FeedUrl -UseBasicParsing -TimeoutSec 60
        if ($Resp.Content -match '(?s)<entry>.*?<title>\s*v?([0-9][^<\s]*)') {
            return $Matches[1]
        }
        Write-Log 'ERROR: release feed has no usable entry'
    } catch {
        Write-Log ("ERROR: failed to fetch release feed: {0}" -f $_.Exception.Message)
    }
    return $null
}

function Read-State {
    if (Test-Path -LiteralPath $StateFile) {
        try {
            return Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Log 'WARN: state file is corrupt, ignoring it'
        }
    }
    return $null
}

function Write-State([string]$LocalVersion, [string]$PackVersion) {
    $Obj = [pscustomobject]@{
        lastLocalVersion   = $LocalVersion
        appliedPackVersion = $PackVersion
        lastRun            = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }
    $Obj | ConvertTo-Json | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function To-Version([string]$Text) {
    try { return [version]$Text } catch { return $null }
}

# ----------------------------------------------------------------------
# 1. Detect versions
# ----------------------------------------------------------------------
$LocalVer = Get-InstalledVersion
if (-not $LocalVer) {
    Write-Log ("ERROR: Termius not found at {0}" -f $TermiusDir)
    exit 1
}

$PackVer = Get-LatestPackVersion
if (-not $PackVer) {
    Write-Log 'ERROR: cannot determine latest pack version, nothing done'
    exit 1
}

$State = Read-State
$StateLocal = if ($State) { $State.lastLocalVersion } else { $null }
$StatePack  = if ($State) { $State.appliedPackVersion } else { $null }

# ----------------------------------------------------------------------
# 2. Decide whether to act
# ----------------------------------------------------------------------
$LocalChanged = ($StateLocal -ne $LocalVer)
if ($Force) { $LocalChanged = $true }

$NewerPackAvailable = $false
$PackV  = To-Version $PackVer
$LocalV = To-Version $LocalVer
if ($StatePack -and $PackVer -ne $StatePack -and $PackV -and $LocalV -and $PackV -le $LocalV) {
    $NewerPackAvailable = $true
}

if (-not $LocalChanged -and -not $NewerPackAvailable) {
    Write-Log ("check: local={0} latest-pack=v{1} applied=(local={2}, pack=v{3}) no action" -f $LocalVer, $PackVer, $StateLocal, $StatePack)
    exit 0
}

# Guard: never apply a pack that is NEWER than the installed Termius.
if ($PackV -and $LocalV -and $PackV -gt $LocalV) {
    Write-Log ("WARN: latest pack v{0} is newer than installed Termius {1}, skipping until Termius catches up" -f $PackVer, $LocalVer)
    exit 0
}

$Reason = if ($LocalChanged) { 'Termius updated' } else { 'new pack available' }
Write-Log ("APPLY: local={0} latest-pack=v{1} (trigger: {2})" -f $LocalVer, $PackVer, $Reason)

# ----------------------------------------------------------------------
# 3. Download the localized asar
# ----------------------------------------------------------------------
$Tmp = $AsarPath + '.tmp'
$VerFile = $AsarPath + '.version'
Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue

$Downloaded = $false
try {
    & curl.exe -sL --connect-timeout 45 --max-time 900 --retry 3 --retry-delay 15 -o $Tmp $DlUrl
    if ($LASTEXITCODE -ne 0) { throw "curl exited with code $LASTEXITCODE" }
    $Size = (Get-Item -LiteralPath $Tmp).Length
    if ($Size -lt 50MB) { throw ("file too small ({0} bytes), not a valid asar" -f $Size) }
    Move-Item -LiteralPath $Tmp -Destination $AsarPath -Force
    Set-Content -LiteralPath $VerFile -Value $PackVer -Encoding ASCII
    $Downloaded = $true
    Write-Log ("downloaded {0} v{1} ({2} MB)" -f $AsarName, $PackVer, [math]::Round($Size / 1MB, 1))
} catch {
    Write-Log ("WARN: download failed ({0})" -f $_.Exception.Message)
    Remove-Item -LiteralPath $Tmp -Force -ErrorAction SilentlyContinue
    # fall back to the previously downloaded file, only if its version matches what we need
    $CachedVer = $null
    if (Test-Path -LiteralPath $VerFile) {
        $CachedVer = (Get-Content -LiteralPath $VerFile -Raw).Trim()
    }
    if ($CachedVer -and $CachedVer -eq $PackVer -and (Test-Path -LiteralPath $AsarPath) -and (Get-Item -LiteralPath $AsarPath).Length -gt 50MB) {
        $Size = (Get-Item -LiteralPath $AsarPath).Length
        Write-Log ("using cached {0} v{1} ({2} MB) as fallback" -f $AsarName, $CachedVer, [math]::Round($Size / 1MB, 1))
        $Downloaded = $true
    } else {
        Write-Log ("WARN: cached pack version '{0}' does not match required v{1}, refusing fallback" -f $CachedVer, $PackVer)
    }
}

if (-not $Downloaded) {
    Write-Log 'ERROR: no usable localized asar available, nothing replaced'
    exit 1
}

# ----------------------------------------------------------------------
# 4. Stop Termius if it is running
# ----------------------------------------------------------------------
$WasRunning = $false
if (Get-Process -Name Termius -ErrorAction SilentlyContinue) {
    $WasRunning = $true
    Stop-Process -Name Termius -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Write-Log 'stopped running Termius processes'
}

# ----------------------------------------------------------------------
# 4.5. Disable asar integrity validation.
#      Termius v10+ refuses to launch when app.asar is replaced unless this
#      Electron fuse (EnableEmbeddedAsarIntegrityValidation) is turned off.
# ----------------------------------------------------------------------
$FusesJs = Join-Path $WorkDir 'disable-fuses.js'
if (-not (Test-Path -LiteralPath $FusesJs)) {
    Set-Content -LiteralPath $FusesJs -Encoding ASCII -Value @'
const { flipFuses, FuseVersion, FuseV1Options } = require('@electron/fuses');
flipFuses(process.argv[2], {
  version: FuseVersion.V1,
  [FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: false
}).then(() => console.log('OK')).catch((e) => { console.error(e.message); process.exit(1); });
'@
}
try {
    $FusesOut = (& node $FusesJs $ExePath 2>&1)
    if ($LASTEXITCODE -eq 0) {
        Write-Log 'disabled asar integrity validation'
    } else {
        Write-Log ("ERROR: failed to disable asar integrity validation: {0}" -f ($FusesOut -join ' '))
        exit 1
    }
} catch {
    Write-Log ("ERROR: fuse disable step failed: {0}" -f $_.Exception.Message)
    exit 1
}

# ----------------------------------------------------------------------
# 5. Backup current app.asar, then replace it
# ----------------------------------------------------------------------
$BackupPath = $null
try {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    if (Test-Path -LiteralPath $AppAsar) {
        # Only back up when the installed app.asar is NOT already our localized
        # pack. Without this guard, a re-apply (e.g. new pack available without
        # a Termius update in between) would overwrite the original backup with
        # the localized file, losing the only rollback copy.
        $AppAsarHash = (Get-FileHash -LiteralPath $AppAsar -Algorithm MD5).Hash
        $PackHash    = (Get-FileHash -LiteralPath $AsarPath -Algorithm MD5).Hash
        if ($AppAsarHash -ne $PackHash) {
            $BackupPath = Join-Path $BackupDir ("app.asar.v{0}.{1}.bak" -f $LocalVer, (Get-Date -Format 'yyyyMMdd-HHmmss'))
            Copy-Item -LiteralPath $AppAsar -Destination $BackupPath -Force
            Write-Log ("backed up original app.asar to {0}" -f $BackupPath)
        } else {
            Write-Log 'skip backup: current app.asar is already the localized pack'
        }
    }
} catch {
    Write-Log ("WARN: backup failed: {0}" -f $_.Exception.Message)
}

try {
    Copy-Item -LiteralPath $AsarPath -Destination $AppAsar -Force
} catch {
    Write-Log ("ERROR: failed to replace app.asar: {0}" -f $_.Exception.Message)
    exit 1
}
Write-Log ("replaced {0}" -f $AppAsar)

# ----------------------------------------------------------------------
# 6. Verify Termius starts with the localized asar; roll back if it crashes
# ----------------------------------------------------------------------
Start-Process -FilePath $ExePath -ErrorAction SilentlyContinue
Start-Sleep -Seconds 12

if (-not (Get-Process -Name Termius -ErrorAction SilentlyContinue)) {
    Write-Log 'ERROR: Termius failed to start with localized asar, rolling back'
    if ($BackupPath -and (Test-Path -LiteralPath $BackupPath)) {
        try {
            Copy-Item -LiteralPath $BackupPath -Destination $AppAsar -Force
            Write-Log ("rolled back app.asar to {0}" -f $BackupPath)
        } catch {
            Write-Log ("ERROR: rollback failed: {0}" -f $_.Exception.Message)
        }
    } else {
        Write-Log 'ERROR: no backup available to roll back to'
    }
    Start-Process -FilePath $ExePath -ErrorAction SilentlyContinue
    exit 1
}

Write-Log 'verified: Termius started OK with localized asar'

# ----------------------------------------------------------------------
# 7. Record state
# ----------------------------------------------------------------------
Write-State $LocalVer $PackVer
Write-Log ("DONE: applied pack v{0} to Termius {1}" -f $PackVer, $LocalVer)

exit 0
