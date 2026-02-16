$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$cliDir = Join-Path $rootDir "android/app/src/main/assets/cli"
$bundleDir = Join-Path $rootDir "android/app/src/main/cli-binaries"
$arm64Dir = Join-Path $cliDir "arm64-v8a"
$armv7Dir = Join-Path $cliDir "armeabi-v7a"
$x86_64Dir = Join-Path $cliDir "x86_64"
$x86Dir = Join-Path $cliDir "x86"
$arm64BundleDir = Join-Path $bundleDir "arm64-v8a"
$armv7BundleDir = Join-Path $bundleDir "armeabi-v7a"
$x86_64BundleDir = Join-Path $bundleDir "x86_64"
$x86BundleDir = Join-Path $bundleDir "x86"

if (-not $env:OOKLA_CLI_AARCH64_TGZ_URL) {
  throw "Missing OOKLA_CLI_AARCH64_TGZ_URL"
}

if (Test-Path $cliDir) {
  Remove-Item -Recurse -Force $cliDir
}
if (Test-Path $bundleDir) {
  Remove-Item -Recurse -Force $bundleDir
}
New-Item -ItemType Directory -Force -Path $arm64Dir | Out-Null
New-Item -ItemType Directory -Force -Path $arm64BundleDir | Out-Null

function Extract-SpeedtestBinary {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$DestinationDir,
    [Parameter(Mandatory = $true)][string]$BundleDestinationDir
  )

  $tempRoot = Join-Path $env:TEMP ("ookla-" + [guid]::NewGuid().ToString("N"))
  $archivePath = Join-Path $tempRoot "ookla.tgz"
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  try {
    Invoke-WebRequest -Uri $Url -OutFile $archivePath
    tar -xzf $archivePath -C $tempRoot speedtest
    Copy-Item -Path (Join-Path $tempRoot "speedtest") -Destination (Join-Path $DestinationDir "speedtest") -Force
    Copy-Item -Path (Join-Path $tempRoot "speedtest") -Destination (Join-Path $BundleDestinationDir "speedtest") -Force
  }
  finally {
    if (Test-Path $tempRoot) {
      Remove-Item -Recurse -Force $tempRoot
    }
  }
}

Extract-SpeedtestBinary -Url $env:OOKLA_CLI_AARCH64_TGZ_URL -DestinationDir $arm64Dir -BundleDestinationDir $arm64BundleDir

if ($env:OOKLA_CLI_ARMHF_TGZ_URL) {
  New-Item -ItemType Directory -Force -Path $armv7Dir | Out-Null
  New-Item -ItemType Directory -Force -Path $armv7BundleDir | Out-Null
  Extract-SpeedtestBinary -Url $env:OOKLA_CLI_ARMHF_TGZ_URL -DestinationDir $armv7Dir -BundleDestinationDir $armv7BundleDir
}

if ($env:OOKLA_CLI_X86_64_TGZ_URL) {
  New-Item -ItemType Directory -Force -Path $x86_64Dir | Out-Null
  New-Item -ItemType Directory -Force -Path $x86_64BundleDir | Out-Null
  Extract-SpeedtestBinary -Url $env:OOKLA_CLI_X86_64_TGZ_URL -DestinationDir $x86_64Dir -BundleDestinationDir $x86_64BundleDir
}

if ($env:OOKLA_CLI_X86_TGZ_URL) {
  New-Item -ItemType Directory -Force -Path $x86Dir | Out-Null
  New-Item -ItemType Directory -Force -Path $x86BundleDir | Out-Null
  Extract-SpeedtestBinary -Url $env:OOKLA_CLI_X86_TGZ_URL -DestinationDir $x86Dir -BundleDestinationDir $x86BundleDir
}

Write-Output "CLI binaries prepared in $cliDir"
Get-ChildItem -Path $cliDir -Recurse -File | ForEach-Object { $_.FullName }
Write-Output "CLI binaries mirrored in $bundleDir"
Get-ChildItem -Path $bundleDir -Recurse -File | ForEach-Object { $_.FullName }
