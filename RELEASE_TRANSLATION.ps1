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
$RequiredFiles = @(
    @{
        InstallName = "~RU_PATCH_1_P.pak"
        ReleaseName = "RU_PATCH_1_P.pak"
    },
    @{
        InstallName = "~RU_QFONT.pak"
        ReleaseName = "RU_QFONT.pak"
    }
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
    param(
        [string]$InstallName,
        [string]$ReleaseName
    )

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
    $responseJson = (& gh api "repos/$Repo/contents/manifest.json?ref=$Branch")
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read manifest.json from GitHub."
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

function Assert-ManifestShape {
    param($Manifest)

    if ($null -eq $Manifest.patcher) {
        throw "manifest.json does not contain the 'patcher' section."
    }

    if ($null -eq $Manifest.translation) {
        throw "manifest.json does not contain the 'translation' section."
    }

    if ($null -eq $Manifest.translation.files) {
        throw "manifest.json does not contain translation.files."
    }

    foreach ($required in $RequiredFiles) {
        $match = @($Manifest.translation.files | Where-Object { [string]$_.name -eq [string]$required.InstallName })
        if ($match.Count -ne 1) {
            throw "manifest.json must contain exactly one entry named '$($required.InstallName)'."
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host " ICE AND FLAME - RELEASE TRANSLATION" -ForegroundColor Green
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

Write-Step "Reading current manifest"
$remote = Read-RemoteManifest
$manifest = $remote.Manifest
$manifestSha = $remote.Sha
Assert-ManifestShape $manifest

$currentVersion = [string]$manifest.translation.version
if ([string]::IsNullOrWhiteSpace($currentVersion)) {
    throw "Current translation version is empty in manifest.json."
}

Write-Host "  Current version: $currentVersion"

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = (Read-Host "Enter new translation version (example: 0.0.1)").Trim()
}

if (-not (Test-VersionFormat $Version)) {
    throw "Invalid version '$Version'. Expected format: X.Y.Z, for example 0.0.1."
}

try {
    $requestedVersion = [version]$Version
    $currentParsedVersion = [version]$currentVersion
}
catch {
    throw "Unable to compare versions '$currentVersion' and '$Version'."
}

if (-not $Force -and $requestedVersion -le $currentParsedVersion) {
    throw "Version $Version must be newer than current translation version $currentVersion. Use -Force only when intentionally republishing the same version."
}

Write-Step "Locating package files"
$resolvedFiles = @()

foreach ($required in $RequiredFiles) {
    $source = Resolve-PackageFile -InstallName $required.InstallName -ReleaseName $required.ReleaseName
    $info = Get-Item -LiteralPath $source

    if ($info.Length -le 0) {
        throw "File '$($info.Name)' is empty."
    }

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

$tag = "translation-$Version"
$title = "ICE AND FLAME Translation $Version"
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
    throw "Release '$tag' already exists. If this is an intentional republish, run RELEASE_TRANSLATION.cmd $Version -Force."
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
        $uploadArgs = @("release", "upload", $tag) + $assets + @("--repo", $Repo, "--clobber")
        Invoke-Gh $uploadArgs
    }
    else {
        $createArgs = @(
            "release", "create", $tag
        ) + $assets + @(
            "--repo", $Repo,
            "--target", $Branch,
            "--title", $title,
            "--notes", "World of Jade Dynasty Russian translation $Version."
        )
        Invoke-Gh $createArgs
    }

    Write-Step "Verifying release assets"
    $releaseJson = (& gh release view $tag --repo $Repo --json tagName,assets)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to read back release '$tag'."
    }

    $releaseData = $releaseJson | ConvertFrom-Json
    $assetNames = @($releaseData.assets | ForEach-Object { $_.name })

    foreach ($file in $resolvedFiles) {
        if ($assetNames -notcontains $file.ReleaseName) {
            throw "Release verification failed: '$($file.ReleaseName)' is missing."
        }
    }

    Write-Step "Updating manifest.json"
    foreach ($file in $resolvedFiles) {
        $manifestEntry = $manifest.translation.files | Where-Object { [string]$_.name -eq [string]$file.InstallName }
        $manifestEntry.url = "$releaseBaseUrl/$($file.ReleaseName)"
        $manifestEntry.sha256 = $file.Sha256
    }

    $manifest.translation.version = $Version

    $json = ($manifest | ConvertTo-Json -Depth 20) + [Environment]::NewLine
    $contentBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))

    $apiArgs = @(
        "api", "--method", "PUT", "repos/$Repo/contents/manifest.json",
        "-f", "message=Release translation $Version",
        "-f", "content=$contentBase64",
        "-f", "sha=$manifestSha",
        "-f", "branch=$Branch"
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
        catch {
            # GitHub raw content may take a few seconds to become visible.
        }

        Start-Sleep -Seconds 3
    }

    if (-not $verified) {
        throw "Release was uploaded, but the public manifest did not verify within 60 seconds."
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor DarkGray
    Write-Host " SUCCESS" -ForegroundColor Green
    Write-Host "==========================================" -ForegroundColor DarkGray
    Write-Host " Translation version: $Version"
    Write-Host " Release tag:         $tag"
    Write-Host " Manifest:            updated and verified"
    Write-Host ""
}
finally {
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
