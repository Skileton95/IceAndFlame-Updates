param(
    [Parameter(Position = 0)]
    [string]$Version,

    [ValidateSet("stable", "beta")]
    [string]$Channel = "stable",

    [string]$ReleaseNotes = "",

    [string]$MinPatcherVersion = "0.0.0",

    [string]$PatchMirrorUrl = "",

    [string]$FontMirrorUrl = "",

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = "Skileton95/IceAndFlame-Updates"
$Branch = "main"
$PackageDir = Join-Path $PSScriptRoot "package"
$ManifestName = if ($Channel -eq "beta") { "manifest-beta.json" } else { "manifest.json" }
$TagPrefix = if ($Channel -eq "beta") { "translation-beta-" } else { "translation-" }

$RequiredFiles = @(
    @{ InstallName = "~RU_PATCH_1_P.pak"; ReleaseName = "RU_PATCH_1_P.pak" },
    @{ InstallName = "~RU_QFONT.pak"; ReleaseName = "RU_QFONT.pak" }
)

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

    throw "Missing translation file. Put '$InstallName' or '$ReleaseName' into '$PackageDir'."
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
    $responseJson = (& gh api "repos/$Repo/contents/${ManifestName}?ref=$Branch")
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read $ManifestName from GitHub."
    }

    $response = $responseJson | ConvertFrom-Json
    $base64 = ([string]$response.content) -replace "\s", ""
    $bytes = [Convert]::FromBase64String($base64)
    $text = [Text.Encoding]::UTF8.GetString($bytes)

    return @{
        Sha = [string]$response.sha
        Manifest = ($text | ConvertFrom-Json)
    }
}

function Ensure-Property {
    param($Object, [string]$Name, $DefaultValue)
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $DefaultValue
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host " ICE AND FLAME - RELEASE TRANSLATION" -ForegroundColor Green
Write-Host " Channel: $Channel" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor DarkGray

Require-Command "gh"

Write-Step "Checking GitHub authentication"
& gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Run: gh auth login"
}

if (-not (Test-Path -LiteralPath $PackageDir)) {
    New-Item -ItemType Directory -Path $PackageDir | Out-Null
}

Write-Step "Reading current $ManifestName"
$remote = Read-RemoteManifest
$manifest = $remote.Manifest
$manifestSha = $remote.Sha

if ($null -eq $manifest.translation -or $null -eq $manifest.translation.files) {
    throw "$ManifestName does not contain a valid translation section."
}

$currentVersion = [string]$manifest.translation.version
Write-Host "  Current version: $currentVersion"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Read-Host "Enter new translation version (example: 0.0.2)").Trim()
}

if (-not (Test-VersionFormat $Version)) {
    throw "Invalid version '$Version'. Expected format: X.Y.Z."
}
if (-not (Test-VersionFormat $MinPatcherVersion)) {
    throw "Invalid MinPatcherVersion '$MinPatcherVersion'. Expected format: X.Y.Z."
}

if (-not $Force) {
    if ([version]$Version -le [version]$currentVersion) {
        throw "Version $Version must be newer than current $currentVersion. Use -Force only for an intentional republish."
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $notesPath = Join-Path $PackageDir "RELEASE_NOTES.txt"
    if (Test-Path -LiteralPath $notesPath -PathType Leaf) {
        $ReleaseNotes = (Get-Content -LiteralPath $notesPath -Raw).Trim()
    }
}
if ([string]::IsNullOrWhiteSpace($ReleaseNotes)) {
    $ReleaseNotes = "Обновление русификатора $Version."
}

Write-Step "Locating package files"
$resolvedFiles = @()
foreach ($required in $RequiredFiles) {
    $source = Resolve-PackageFile -InstallName $required.InstallName -ReleaseName $required.ReleaseName
    $info = Get-Item -LiteralPath $source
    if ($info.Length -le 0) { throw "File '$($info.Name)' is empty." }

    $resolvedFiles += [pscustomobject]@{
        InstallName = $required.InstallName
        ReleaseName = $required.ReleaseName
        Source = $source
        Size = $info.Length
        Sha256 = Get-Sha256Lower $source
    }
}

foreach ($file in $resolvedFiles) {
    Write-Host ("  {0,-20} {1,8:N1} MB  {2}" -f $file.ReleaseName, ($file.Size / 1MB), $file.Sha256)
}

$tag = "$TagPrefix$Version"
$title = if ($Channel -eq "beta") {
    "ICE AND FLAME Translation $Version BETA"
} else {
    "ICE AND FLAME Translation $Version"
}
$releaseBaseUrl = "https://github.com/$Repo/releases/download/$tag"

Write-Step "Checking release tag $tag"
$previousErrorActionPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = "Continue"
    & gh release view $tag --repo $Repo --json tagName 1>$null 2>$null
    $releaseExists = ($LASTEXITCODE -eq 0)
}
finally {
    $ErrorActionPreference = $previousErrorActionPreference
}

if ($releaseExists -and -not $Force) {
    throw "Release '$tag' already exists. Use -Force only when intentionally republishing it."
}

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("IceAndFlame-Translation-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    $assets = @()
    foreach ($file in $resolvedFiles) {
        $assetPath = Join-Path $tempDir $file.ReleaseName
        Copy-Item -LiteralPath $file.Source -Destination $assetPath -Force
        $assets += $assetPath
    }

    Write-Step "Publishing GitHub Release $tag"
    if ($releaseExists) {
        Invoke-Gh (@("release", "upload", $tag) + $assets + @("--repo", $Repo, "--clobber"))
    }
    else {
        Invoke-Gh (@(
            "release", "create", $tag
        ) + $assets + @(
            "--repo", $Repo,
            "--target", $Branch,
            "--title", $title,
            "--notes", $ReleaseNotes
        ))
    }

    Write-Step "Verifying release assets"
    $releaseJson = (& gh release view $tag --repo $Repo --json tagName,assets)
    if ($LASTEXITCODE -ne 0) { throw "Unable to read back release '$tag'." }
    $releaseData = $releaseJson | ConvertFrom-Json
    $assetNames = @($releaseData.assets | ForEach-Object { $_.name })

    foreach ($file in $resolvedFiles) {
        if ($assetNames -notcontains $file.ReleaseName) {
            throw "Release verification failed: '$($file.ReleaseName)' is missing."
        }
    }

    Write-Step "Updating $ManifestName"
    Ensure-Property $manifest "schemaVersion" 2
    Ensure-Property $manifest "channel" $Channel
    $manifest.schemaVersion = 2
    $manifest.channel = $Channel

    Ensure-Property $manifest.translation "minPatcherVersion" "0.0.0"
    Ensure-Property $manifest.translation "releaseNotes" ""
    $manifest.translation.version = $Version
    $manifest.translation.minPatcherVersion = $MinPatcherVersion
    $manifest.translation.releaseNotes = $ReleaseNotes

    foreach ($file in $resolvedFiles) {
        $entry = $manifest.translation.files | Where-Object { [string]$_.name -eq [string]$file.InstallName }
        if ($null -eq $entry) {
            throw "$ManifestName is missing file entry '$($file.InstallName)'."
        }

        Ensure-Property $entry "urls" @()
        $entry.url = "$releaseBaseUrl/$($file.ReleaseName)"

        $mirror = if ($file.InstallName -eq "~RU_PATCH_1_P.pak") {
            $PatchMirrorUrl
        } else {
            $FontMirrorUrl
        }

        $entry.urls = if ([string]::IsNullOrWhiteSpace($mirror)) { @() } else { @($mirror.Trim()) }
        $entry.sha256 = $file.Sha256
    }

    $json = ($manifest | ConvertTo-Json -Depth 30) + [Environment]::NewLine
    $contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

    $apiArgs = @(
        "api", "--method", "PUT", "repos/$Repo/contents/$ManifestName",
        "-f", "message=Release $Channel translation $Version",
        "-f", "content=$contentBase64",
        "-f", "sha=$manifestSha",
        "-f", "branch=$Branch"
    )

    & gh @apiArgs | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to update $ManifestName on GitHub."
    }

    Write-Step "Checking public $ManifestName"
    $verified = $false
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        try {
            $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            $publicUrl = "https://raw.githubusercontent.com/$Repo/$Branch/${ManifestName}?ts=$cacheBust"
            $publicManifest = Invoke-RestMethod -Uri $publicUrl -Headers @{ "Cache-Control" = "no-cache" }

            if ([string]$publicManifest.translation.version -ne $Version) {
                throw "Public manifest still reports version $($publicManifest.translation.version)."
            }

            $allHashesMatch = $true
            foreach ($file in $resolvedFiles) {
                $publicEntry = $publicManifest.translation.files | Where-Object { [string]$_.name -eq [string]$file.InstallName }
                if ($null -eq $publicEntry -or [string]$publicEntry.sha256 -ne [string]$file.Sha256) {
                    $allHashesMatch = $false
                    break
                }
            }

            if ($allHashesMatch) {
                $verified = $true
                break
            }
        }
        catch { }

        Start-Sleep -Seconds 3
    }

    if (-not $verified) {
        throw "Release was uploaded, but the public manifest did not verify within 60 seconds."
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkGray
    Write-Host " SUCCESS" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor DarkGray
    Write-Host " Channel:             $Channel"
    Write-Host " Translation version: $Version"
    Write-Host " Release tag:         $tag"
    Write-Host " Minimum patcher:     $MinPatcherVersion"
    Write-Host " Manifest:            $ManifestName"
    Write-Host ""
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
