<#
.SYNOPSIS
  Build an unsigned iOS .ipa for RunThru on Windows using iosbox (Docker).

.DESCRIPTION
  Wraps the iosbox Docker workflow:
    1. (One-time) Setup: extract Xcode SDK from Xcode.xip into a Docker volume.
    2. Build: cross-compile Flutter app -> build/iosbox/Runner.ipa (unsigned).

  After build, sign + install with AltStore / Sideloadly / MobAI.

.PARAMETER Setup
  Run the one-time SDK extraction. Requires -XcodeXip path.

.PARAMETER XcodeXip
  Path to Xcode_26.3_*.xip (download from developer.apple.com with free Apple ID).

.PARAMETER Image
  iosbox Docker image tag. Defaults to mobaiapp/iosbox:flutter-3.41.0.
  Note: the image pins Flutter version; project's pubspec is informational only.

.EXAMPLE
  # One-time SDK setup
  ./scripts/iosbox-build.ps1 -Setup -XcodeXip C:\xcode\Xcode_26.3_Apple_silicon.xip

.EXAMPLE
  # Build IPA
  ./scripts/iosbox-build.ps1
#>
[CmdletBinding()]
param(
  [switch]$Setup,
  [string]$XcodeXip,
  [string]$Image = 'mobaiapp/iosbox:flutter-3.41.0'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path "$PSScriptRoot\..").Path

function Assert-Docker {
  try { docker info *> $null } catch {
    throw 'Docker is not running. Start Docker Desktop and retry.'
  }
}

Assert-Docker

if ($Setup) {
  if (-not $XcodeXip) { throw '-XcodeXip is required for -Setup' }
  if (-not (Test-Path $XcodeXip)) { throw "Xcode.xip not found at: $XcodeXip" }

  $xipFull = (Resolve-Path $XcodeXip).Path
  Write-Host "==> One-time SDK extraction from $xipFull" -ForegroundColor Cyan
  Write-Host '    This takes 10-30 min and uses ~30 GB of disk in the iosbox-sdk volume.'

  docker run --rm `
    -v "${xipFull}:/workspace/Xcode.xip" `
    -v 'iosbox-sdk:/root/.iosbox' `
    $Image iosbox setup /workspace/Xcode.xip

  if ($LASTEXITCODE -ne 0) { throw 'iosbox setup failed' }
  Write-Host '==> SDK setup complete. Run without -Setup to build.' -ForegroundColor Green
  exit 0
}

# Build path
$projectMount = $projectRoot -replace '\\', '/'
# Docker on Windows needs the Linux-style path for bind mounts
$projectMount = "/$($projectMount -replace ':', '')"

Write-Host "==> Building unsigned IPA from $projectRoot" -ForegroundColor Cyan

docker run --rm `
  -v 'iosbox-sdk:/root/.iosbox' `
  -v "${projectRoot}:/project" `
  -v 'iosbox-swift-cache-runthru:/root/.cache/org.swift.swiftpm' `
  -v 'iosbox-build-cache-runthru:/tmp/iosbox-native-build' `
  $Image iosbox build /project

if ($LASTEXITCODE -ne 0) {
  Write-Host '==> Build failed.' -ForegroundColor Red
  Write-Host '    Common causes:'
  Write-Host '    - A plugin lacks SwiftPM support (pdfrx, file_picker, permission_handler, etc.)'
  Write-Host '    - Share Extension target needs Package.swift wiring'
  Write-Host '    See doc/iosbox-setup.md for troubleshooting.'
  exit 1
}

$ipa = Join-Path $projectRoot 'build\iosbox\Runner.ipa'
if (Test-Path $ipa) {
  Write-Host "==> Build OK: $ipa" -ForegroundColor Green
  Write-Host '    Next: sign + install on iPhone.'
  Write-Host '    Free option: Sideloadly (https://sideloadly.io) with your Apple ID.'
  Write-Host '    Paid OTA:    https://mobai.run'
} else {
  Write-Warning "Build reported success but IPA not found at $ipa"
}
