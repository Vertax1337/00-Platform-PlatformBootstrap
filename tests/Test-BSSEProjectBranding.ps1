[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
. "$repoRoot\bootstrap\BSSE.AzureDevOps.Branding.ps1"

$expected = @{
    'assets/project-icons/00-platform.png' = @{
        Sha256 = 'd09fe250785cb6dfe2269be4f0e789adc7bcb8859aaeac550b63075d0a25559a'
        Length = 1346475
    }
    'assets/project-icons/10-automation.png' = @{
        Sha256 = 'c673ee98d829ea1b21e454335be0b4c67db211a27831bc21b615f650a49d0b1d'
        Length = 1419904
    }
    'assets/project-icons/20-iac.png' = @{
        Sha256 = '365adb26f192d749539c85e8f9dd236dd3453069278afece20443883510ac709'
        Length = 1524709
    }
    'assets/project-icons/99-lab.png' = @{
        Sha256 = 'bc5439b7b2edd67e56598e82310bb8e12cf1d949954fea6c631404d5fb8797d0'
        Length = 1580858
    }
    'assets/project-icons/cust-generic.png' = @{
        Sha256 = '7baa33edd81b0d6418cfd7cf65da68dd97cc71f51e34020c6b987633d2f481a0'
        Length = 1493916
    }
}

$mapping = @{
    '00-Platform' = 'assets/project-icons/00-platform.png'
    '10-Automation' = 'assets/project-icons/10-automation.png'
    '20-IaC' = 'assets/project-icons/20-iac.png'
    '99-LAB' = 'assets/project-icons/99-lab.png'
    'CUST-00000-Bernd-Schneider-Software-Engineering-GmbH' = 'assets/project-icons/cust-generic.png'
    'CUST-11941-Cannon-Deutschland-GmbH' = 'assets/project-icons/cust-generic.png'
}

foreach ($case in $mapping.GetEnumerator()) {
    $actual = Get-BSSEProjectAvatarAssetRelativePath -ProjectName $case.Key
    if ($actual -ne $case.Value) {
        throw "Branding mapping mismatch for '$($case.Key)': expected '$($case.Value)', got '$actual'."
    }
}

# 30-IDD is now a managed Core project, but its approved source asset is not yet
# versioned in PlatformBootstrap. Until that asset is explicitly added, the branding
# resolver must return no mapping so that no unrelated Core icon is used as fallback.
$pendingIdd = Get-BSSEProjectAvatarAssetRelativePath -ProjectName '30-IDD'
if ($null -ne $pendingIdd) {
    throw "30-IDD unexpectedly received branding mapping '$pendingIdd' before an approved 30-idd.png is versioned."
}

$unknown = Get-BSSEProjectAvatarAssetRelativePath -ProjectName 'Unmanaged-Project'
if ($null -ne $unknown) {
    throw "Unmanaged project unexpectedly received branding mapping '$unknown'."
}

[byte[]]$pngSignature = @(0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A)

foreach ($entry in $expected.GetEnumerator()) {
    $relative = $entry.Key
    $path = Join-Path $repoRoot ($relative -replace '/', [System.IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Expected branding asset missing: $relative"
    }

    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -ne [int64]$entry.Value.Length) {
        throw "Branding asset length mismatch for '$relative': expected $($entry.Value.Length), got $($bytes.Length)."
    }

    for ($i = 0; $i -lt $pngSignature.Length; $i++) {
        if ($bytes[$i] -ne $pngSignature[$i]) {
            throw "Invalid PNG signature: $relative"
        }
    }

    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $entry.Value.Sha256) {
        throw "Branding asset SHA-256 mismatch for '$relative': expected $($entry.Value.Sha256), got $hash."
    }
}

Write-Host '[OK] Project-branding mapping, pending 30-IDD behavior and all five approved source assets are consistent.' -ForegroundColor Green
