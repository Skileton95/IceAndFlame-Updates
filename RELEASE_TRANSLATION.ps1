param(
    [Parameter(Position = 0)]
    [string]$Version,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = "Skileton95/IceAndFlame-Updates"
$Branch = "main"
$PackageDir = Join-Path $PSScriptRoot "package"
$ManifestPath = Join-Path $PSScriptRoot "manifest.json"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "'$Command $($Arguments -join ' ')' failed with exit code $LASTEXITCODE."
    }
}

function Resolve-PackageFile {
    param(
        [string]$InstallName,
        [string]$ReleaseName
    )

    $candidates = @(
        (Join-Path $PackageDir $InstallName),
        (Join-Path $PackageDir $ReleaseName)
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "Missing translation file. Put '$InstallName' (or '$ReleaseName') into '$PackageDir'."
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Test-VersionFormat {
    param([string]$Value)
    return $Value -match '^\d+\.\d+\.\d+$'
}

Write-Host "ICE AND FLAME - translation publisher" -ForegroundColor Green

Require-Command "git"
Require-Command "gh"

Write-Step "Checking GitHub authentication"
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

Set-Location $PSScriptRoot

if (-not (Test-Path -LiteralPath $PackageDir)) {
    New-Item -ItemType Directory -Path $PackageDir | Out-Null
}

Write-Step "Checking local repository"
$repoRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $repoRoot) {
    throw "This script must be run from a clone of the IceAndFlame-Updates repository."
}

$dirty = (& git status --porcelain --untracked-files=no)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to read git status."
}

if ($dirty) {
    throw "Tracked files have local changes. Commit or revert them before publishing a translation."
}

$currentBranch = (& git branch --show-current).Trim()
if ($currentBranch -ne $Branch) {
    throw "Current branch is '$currentBranch'. Switch to '$Branch' before publishing."
}

Write-Step "Updating local main from GitHub"
Invoke-Native git fetch origin $Branch
Invoke-Native git pull --ff-only origin $Branch

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "manifest.json was not found at '$ManifestPath'."
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentVersion = [string]$manifest.translation.version

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Current translation version: $currentVersion"
    $Version = (Read-Host "Enter new translation version (example: 4.09.29)").Trim()
}

if (-not (Test-VersionFormat $Version)) {
    throw "Invalid version '$Version'. Expected format: X.XX.XX (example: 4.09.29)."
}

if (-not $Force) {
    $requested = [version]$Version
    $current = [version]$currentVersion

    if ($requested -le $current) {
        throw "Version $Version is not newer than current manifest version $currentVersion. Use a newer version or run with -Force."
    }
}

Write-Step "Locating package files"
$patchSource = Resolve-PackageFile "~RU_PATCH_1_P.pak" "RU_PATCH_1_P.pak"
$fontSource = Resolve-PackageFile "~RU_QFONT.pak" "RU_QFONT.pak"

$patchInfo = Get-Item -LiteralPath $patchSource
$fontInfo = Get-Item -LiteralPath $fontSource

if ($patchInfo.Length -lt 1MB) {
    throw "RU_PATCH_1_P.pak looks too small: $($patchInfo.Length) bytes."
}
if ($fontInfo.Length -lt 1MB) {
    throw "RU_QFONT.pak looks too small: $($fontInfo.Length) bytes."
}

Write-Host ("  PATCH: {0:N1} MB" -f ($patchInfo.Length / 1MB))
Write-Host ("  QFONT: {0:N1} MB" -f ($fontInfo.Length / 1MB))

Write-Step "Calculating SHA-256"
$patchSha = Get-Sha256Lower $patchSource
$fontSha = Get-Sha256Lower $fontSource
Write-Host "  RU_PATCH_1_P.pak  $patchSha"
Write-Host "  RU_QFONT.pak      $fontSha"

$tag = "translation-$Version"
$title = "Russian Translation $Version"
$releaseBaseUrl = "https://github.com/$Repo/releases/download/$tag"

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("IceAndFlame-Translation-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $patchAsset = Join-Path $tempDir "RU_PATCH_1_P.pak"
    $fontAsset = Join-Path $tempDir "RU_QFONT.pak"

    Copy-Item -LiteralPath $patchSource -Destination $patchAsset
    Copy-Item -LiteralPath $fontSource -Destination $fontAsset

    Write-Step "Publishing GitHub Release $tag"

    & gh release view $tag --repo $Repo --json tagName *> $null
    $releaseExists = ($LASTEXITCODE -eq 0)

    if ($releaseExists) {
        if (-not $Force) {
            throw "Release '$tag' already exists. Use -Force only if you intentionally want to replace its assets."
        }

        Invoke-Native gh release upload $tag $patchAsset $fontAsset --repo $Repo --clobber
    }
    else {
        Invoke-Native gh release create $tag $patchAsset $fontAsset --repo $Repo --target $Branch --title $title --notes "World of Jade Dynasty Russian translation $Version."
    }

    Write-Step "Verifying release assets"
    $releaseJson = (& gh release view $tag --repo $Repo --json tagName,assets)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read back release '$tag'."
    }

    $releaseData = $releaseJson | ConvertFrom-Json
    $assetNames = @($releaseData.assets | ForEach-Object { $_.name })

    foreach ($requiredAsset in @("RU_PATCH_1_P.pak", "RU_QFONT.pak")) {
        if ($assetNames -notcontains $requiredAsset) {
            throw "Release verification failed: '$requiredAsset' is missing from '$tag'."
        }
    }

    Write-Step "Updating manifest.json"

    $expected = @{
        "~RU_PATCH_1_P.pak" = @{
            Asset = "RU_PATCH_1_P.pak"
            Sha = $patchSha
        }
        "~RU_QFONT.pak" = @{
            Asset = "RU_QFONT.pak"
            Sha = $fontSha
        }
    }

    $seen = @{}

    foreach ($file in $manifest.translation.files) {
        $installName = [string]$file.name

        if ($expected.ContainsKey($installName)) {
            $definition = $expected[$installName]
            $file.url = "$releaseBaseUrl/$($definition.Asset)"
            $file.sha256 = $definition.Sha
            $seen[$installName] = $true
        }
    }

    foreach ($requiredName in $expected.Keys) {
        if (-not $seen.ContainsKey($requiredName)) {
            throw "manifest.json does not contain translation entry '$requiredName'."
        }
    }

    $manifest.translation.version = $Version

    $json = $manifest | ConvertTo-Json -Depth 20
    Write-Utf8NoBom $ManifestPath ($json + [Environment]::NewLine)

    Write-Step "Committing manifest to main"
    Invoke-Native git add -- manifest.json

    & git diff --cached --quiet
    $hasChanges = ($LASTEXITCODE -ne 0)

    if ($hasChanges) {
        Invoke-Native git commit -m "Release translation $Version"
        Invoke-Native git push origin $Branch
    }
    else {
        Write-Host "manifest.json already contains these values; no commit was needed."
    }

    Write-Step "Checking public manifest.json"

    $verified = $false
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $publicUrl = "https://raw.githubusercontent.com/$Repo/$Branch/manifest.json?ts=$cacheBust"
            $publicManifest = Invoke-RestMethod -Uri $publicUrl -Headers @{ "Cache-Control" = "no-cache" }

            $publicPatch = $publicManifest.translation.files | Where-Object { $_.name -eq "~RU_PATCH_1_P.pak" }
            $publicFont = $publicManifest.translation.files | Where-Object { $_.name -eq "~RU_QFONT.pak" }

            if (
                [string]$publicManifest.translation.version -eq $Version -and
                [string]$publicPatch.sha256 -eq $patchSha -and
                [string]$publicFont.sha256 -eq $fontSha
            ) {
                $verified = $true
                break
            }
        }
        catch {
            # GitHub/raw propagation may briefly lag after push.
        }

        Start-Sleep -Seconds 3
    }

    if (-not $verified) {
        throw "Release was uploaded, but the public manifest did not verify within 60 seconds."
    }

    Write-Host ""
    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host "Translation version: $Version"
    Write-Host "Release: https://github.com/$Repo/releases/tag/$tag"
    Write-Host "Public manifest: https://raw.githubusercontent.com/$Repo/$Branch/manifest.json"
    Write-Host ""
    Write-Host "The patcher will install the files as:"
    Write-Host "  ~RU_PATCH_1_P.pak"
    Write-Host "  ~RU_QFONT.pak"
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
