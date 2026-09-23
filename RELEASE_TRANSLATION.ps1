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

function Invoke-Gh {
    param([string[]]$ArgsList)
    & gh @ArgsList
    if ($LASTEXITCODE -ne 0) {
        throw "gh command failed with exit code $LASTEXITCODE."
    }
}

function Resolve-PackageFile {
    param([string]$InstallName, [string]$ReleaseName)
    foreach ($name in @($InstallName, $ReleaseName)) {
        $candidate = Join-Path $PackageDir $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw "Missing translation file. Put $InstallName or $ReleaseName into $PackageDir."
}

function Get-Sha256Lower {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-VersionFormat {
    param([string]$Value)
    return $Value -match '^\d+\.\d+\.\d+$'
}

function Read-RemoteManifest {
    $responseJson = (& gh api "repos/$Repo/contents/manifest.json?ref=$Branch")
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read manifest.json from GitHub."
    }
    $response = $responseJson | ConvertFrom-Json
    $base64 = ([string]$response.content) -replace "\s", ""
    $bytes = [Convert]::FromBase64String($base64)
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    return @{ Sha = [string]$response.sha; Manifest = ($text | ConvertFrom-Json) }
}

Write-Host "ICE AND FLAME - translation publisher" -ForegroundColor Green

Require-Command "gh"

Write-Step "Checking GitHub authentication"
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

if (-not (Test-Path -LiteralPath $PackageDir)) {
    New-Item -ItemType Directory -Path $PackageDir | Out-Null
}

Write-Step "Locating package files"
$patchSource = Resolve-PackageFile "~RU_PATCH_1_P.pak" "RU_PATCH_1_P.pak"
$fontSource = Resolve-PackageFile "~RU_QFONT.pak" "RU_QFONT.pak"

$patchInfo = Get-Item -LiteralPath $patchSource
$fontInfo = Get-Item -LiteralPath $fontSource
if ($patchInfo.Length -lt 1MB) { throw "RU_PATCH_1_P.pak looks too small." }
if ($fontInfo.Length -lt 1MB) { throw "RU_QFONT.pak looks too small." }

Write-Host ("  PATCH: {0:N1} MB" -f ($patchInfo.Length / 1MB))
Write-Host ("  QFONT: {0:N1} MB" -f ($fontInfo.Length / 1MB))

Write-Step "Reading current manifest from GitHub"
$remote = Read-RemoteManifest
$manifest = $remote.Manifest
$manifestSha = $remote.Sha
$currentVersion = [string]$manifest.translation.version

if ([string]::IsNullOrWhiteSpace($Version)) {
    Write-Host "Current translation version: $currentVersion"
    $Version = (Read-Host "Enter new translation version (example: 4.09.29)").Trim()
}

if (-not (Test-VersionFormat $Version)) {
    throw "Invalid version $Version. Expected format: X.XX.XX"
}

if (-not $Force) {
    $requested = [version]$Version
    $current = [version]$currentVersion
    if ($requested -le $current) {
        throw "Version $Version is not newer than current manifest version $currentVersion."
    }
}

Write-Step "Calculating SHA-256"
$patchSha = Get-Sha256Lower $patchSource
$fontSha = Get-Sha256Lower $fontSource
Write-Host "  RU_PATCH_1_P.pak  $patchSha"
Write-Host "  RU_QFONT.pak      $fontSha"

$tag = "translation-$Version"
$title = "Russian Translation $Version"
$releaseBaseUrl = "https://github.com/$Repo/releases/download/$tag"

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("IceAndFlame-Translation-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $patchAsset = Join-Path $tempDir "RU_PATCH_1_P.pak"
    $fontAsset = Join-Path $tempDir "RU_QFONT.pak"
    Copy-Item -LiteralPath $patchSource -Destination $patchAsset
    Copy-Item -LiteralPath $fontSource -Destination $fontAsset

    Write-Step "Publishing GitHub Release $tag"
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & gh release view $tag --repo $Repo --json tagName 1>$null 2>$null
        $releaseExists = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($releaseExists) {
        if (-not $Force) { throw "Release $tag already exists." }
        Invoke-Gh @("release","upload",$tag,$patchAsset,$fontAsset,"--repo",$Repo,"--clobber")
    }
    else {
        Invoke-Gh @("release","create",$tag,$patchAsset,$fontAsset,"--repo",$Repo,"--target",$Branch,"--title",$title,"--notes","World of Jade Dynasty Russian translation $Version.")
    }

    Write-Step "Verifying release assets"
    $releaseJson = (& gh release view $tag --repo $Repo --json tagName,assets)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read back release $tag." }
    $releaseData = $releaseJson | ConvertFrom-Json
    $assetNames = @($releaseData.assets | ForEach-Object { $_.name })
    foreach ($requiredAsset in @("RU_PATCH_1_P.pak","RU_QFONT.pak")) {
        if ($assetNames -notcontains $requiredAsset) {
            throw "Release verification failed: $requiredAsset is missing."
        }
    }

    Write-Step "Updating manifest.json"
    foreach ($file in $manifest.translation.files) {
        if ([string]$file.name -eq "~RU_PATCH_1_P.pak") {
            $file.url = "$releaseBaseUrl/RU_PATCH_1_P.pak"
            $file.sha256 = $patchSha
        }
        elseif ([string]$file.name -eq "~RU_QFONT.pak") {
            $file.url = "$releaseBaseUrl/RU_QFONT.pak"
            $file.sha256 = $fontSha
        }
    }
    $manifest.translation.version = $Version
    $json = ($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    $contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

    $apiArgs = @(
        "api","--method","PUT","repos/$Repo/contents/manifest.json",
        "-f","message=Release translation $Version",
        "-f","content=$contentBase64",
        "-f","sha=$manifestSha",
        "-f","branch=$Branch"
    )
    & gh @apiArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to update manifest.json on GitHub."
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
            if ([string]$publicManifest.translation.version -eq $Version -and [string]$publicPatch.sha256 -eq $patchSha -and [string]$publicFont.sha256 -eq $fontSha) {
                $verified = $true
                break
            }
        }
        catch { }
        Start-Sleep -Seconds 3
    }

    if (-not $verified) {
        throw "Release uploaded, but public manifest did not verify within 60 seconds."
    }

    Write-Host ""
    Write-Host "SUCCESS" -ForegroundColor Green
    Write-Host "Translation version: $Version"
    Write-Host "Release: https://github.com/$Repo/releases/tag/$tag"
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
