param(
    [switch]$NoPub
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
$flutterPath = if (Test-Path 'C:\flutter\bin\flutter.bat') {
    'C:\flutter\bin\flutter.bat'
} elseif ($env:FLUTTER_ROOT -and (Test-Path (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'))) {
    Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
} else {
    throw 'Set FLUTTER_ROOT or install Flutter at C:\flutter.'
}

$pubspecText = [System.IO.File]::ReadAllText($pubspecPath)
$versionPattern = '(?m)^version:\s*(?<name>\d+\.\d+\.\d+)\+(?<build>\d+)\s*$'
$versionMatch = [regex]::Match($pubspecText, $versionPattern)
if (-not $versionMatch.Success) {
    throw 'pubspec.yaml must contain a version in the form version: x.y.z+N.'
}

$versionName = $versionMatch.Groups['name'].Value
$currentBuild = [int64]$versionMatch.Groups['build'].Value
$nextBuild = $currentBuild + 1
$nextVersion = "$versionName+$nextBuild"
$updatedPubspecText = [regex]::Replace(
    $pubspecText,
    $versionPattern,
    "version: $nextVersion",
    1
)
$utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false

$buildArgs = @('build', 'apk', '--release', '--split-per-abi')
if ($NoPub) {
    $buildArgs += '--no-pub'
}

$buildSucceeded = $false
try {
    [System.IO.File]::WriteAllText($pubspecPath, $updatedPubspecText, $utf8NoBom)
    Write-Host "Building Liflow $versionName+$nextBuild (previous build $currentBuild)..."

    & $flutterPath @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter release build failed with exit code $LASTEXITCODE."
    }

    $outputDirectory = Join-Path $projectRoot 'build\app\outputs\flutter-apk'
    $abiNames = @('arm64-v8a', 'armeabi-v7a', 'x86_64')
    foreach ($abi in $abiNames) {
        $source = Join-Path $outputDirectory "app-$abi-release.apk"
        if (-not (Test-Path $source)) {
            throw "Expected ABI APK was not generated: $source"
        }

        $target = Join-Path $outputDirectory "Liflow-v$versionName-build$nextBuild-$abi-release.apk"
        Copy-Item -LiteralPath $source -Destination $target -Force
        Write-Host "Created $target"
    }

    $buildSucceeded = $true
}
finally {
    if (-not $buildSucceeded) {
        [System.IO.File]::WriteAllText($pubspecPath, $pubspecText, $utf8NoBom)
        Write-Warning 'Release build failed; restored the previous pubspec version.'
    }
}
