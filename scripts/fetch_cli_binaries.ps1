$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent $PSScriptRoot
$cliDir = Join-Path $rootDir "android/app/src/main/assets/cli"
New-Item -ItemType Directory -Force -Path $cliDir | Out-Null

if ($env:OOKLA_CLI_URL) {
  Invoke-WebRequest -Uri $env:OOKLA_CLI_URL -OutFile (Join-Path $cliDir "speedtest")
}

if ($env:PYTHON_SPEEDTEST_CLI_URL) {
  Invoke-WebRequest -Uri $env:PYTHON_SPEEDTEST_CLI_URL -OutFile (Join-Path $cliDir "speedtest-cli")
}

Write-Output "CLI binaries prepared in $cliDir"
