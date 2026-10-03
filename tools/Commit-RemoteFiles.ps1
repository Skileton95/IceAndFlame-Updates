param(
    [Parameter(Mandatory)][string]$Repo,
    [string]$Branch = "main",
    [Parameter(Mandatory)][string]$Message,
    [Parameter(Mandatory)][hashtable]$Files,
    [hashtable]$ExpectedHashes = @{}
)
$ErrorActionPreference = "Stop"
function Get-Api([string]$Endpoint) {
    $json = gh api $Endpoint
    if ($LASTEXITCODE -ne 0) { throw "Cannot read $Endpoint" }
    return ($json | ConvertFrom-Json)
}
function Post-Api([string]$Endpoint, [object]$Payload, [string]$Method = "POST") {
    $result = ($Payload | ConvertTo-Json -Depth 100 -Compress) | gh api --method $Method $Endpoint --input -
    if ($LASTEXITCODE -ne 0) { throw "Cannot update $Endpoint" }
    return ($result | ConvertFrom-Json)
}
$ref = Get-Api "repos/$Repo/git/ref/heads/$Branch"
foreach ($path in $ExpectedHashes.Keys) {
    $actual = Get-Api "repos/$Repo/contents/${path}?ref=$($ref.object.sha)"
    if ([string]$actual.sha -ne [string]$ExpectedHashes[$path]) { throw "Remote $path changed while preparing publication." }
}
$parent = Get-Api "repos/$Repo/git/commits/$($ref.object.sha)"
$entries = @(
    foreach ($path in $Files.Keys) {
        if ($path.StartsWith("/") -or $path.Contains("..")) { throw "Invalid repository path." }
        @{ path=$path; mode="100644"; type="blob"; content=[IO.File]::ReadAllText($Files[$path], [Text.Encoding]::UTF8) }
    }
)
$tree = Post-Api "repos/$Repo/git/trees" @{ base_tree=$parent.tree.sha; tree=$entries }
$commit = Post-Api "repos/$Repo/git/commits" @{ message=$Message; tree=$tree.sha; parents=@($ref.object.sha) }
[void](Post-Api "repos/$Repo/git/refs/heads/$Branch" @{ sha=$commit.sha; force=$false } "PATCH")
Write-Host "Published $($Files.Count) files atomically in commit $($commit.sha)."
