$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$cliDir = Join-Path $rootDir "android/app/src/main/assets/cli"
$arm64Dir = Join-Path $cliDir "arm64-v8a"
$armv7Dir = Join-Path $cliDir "armeabi-v7a"

if (-not $env:OOKLA_CLI_AARCH64_TGZ_URL) {
  throw "Missing OOKLA_CLI_AARCH64_TGZ_URL"
}

if (Test-Path $cliDir) {
  Remove-Item -Recurse -Force $cliDir
}
New-Item -ItemType Directory -Force -Path $arm64Dir | Out-Null

function Extract-SpeedtestBinary {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$DestinationDir
  )

  $tempRoot = Join-Path $env:TEMP ("ookla-" + [guid]::NewGuid().ToString("N"))
  $archivePath = Join-Path $tempRoot "ookla.tgz"
  New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
  try {
    Invoke-WebRequest -Uri $Url -OutFile $archivePath
    tar -xzf $archivePath -C $tempRoot speedtest
    Copy-Item -Path (Join-Path $tempRoot "speedtest") -Destination (Join-Path $DestinationDir "speedtest") -Force
  }
  finally {
    if (Test-Path $tempRoot) {
      Remove-Item -Recurse -Force $tempRoot
    }
  }
}

Extract-SpeedtestBinary -Url $env:OOKLA_CLI_AARCH64_TGZ_URL -DestinationDir $arm64Dir

if ($env:OOKLA_CLI_ARMHF_TGZ_URL) {
  New-Item -ItemType Directory -Force -Path $armv7Dir | Out-Null
  Extract-SpeedtestBinary -Url $env:OOKLA_CLI_ARMHF_TGZ_URL -DestinationDir $armv7Dir
}

Write-Output "CLI binaries prepared in $cliDir"
Get-ChildItem -Path $cliDir -Recurse -File | ForEach-Object { $_.FullName }
