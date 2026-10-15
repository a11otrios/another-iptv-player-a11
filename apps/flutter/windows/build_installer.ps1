[CmdletBinding()]
param(
  [string]$NsisPath,
  [string]$VcRedistPath,
  [string]$Version = "1.7.11",
  [string]$BuildNumber = "42"
)

$ErrorActionPreference = "Stop"

$windowsDir = $PSScriptRoot
$projectDir = Split-Path -Parent $windowsDir
$workspaceDir = (Resolve-Path (Join-Path $projectDir "..\..")).Path
$releaseDir = Join-Path $projectDir "build\windows\x64\runner\Release"
$outputDir = Join-Path $projectDir "build\installer"
$installerScript = Join-Path $windowsDir "installer.nsi"

if (-not (Test-Path -LiteralPath (Join-Path $releaseDir "iptv_player.exe"))) {
  throw "Windows release build not found. Run 'flutter build windows' first."
}

$ffmpegPath = Join-Path $releaseDir "tools\ffmpeg\ffmpeg.exe"
if (-not (Test-Path -LiteralPath $ffmpegPath)) {
  throw "Bundled FFmpeg was not found. Run 'windows\prepare_ffmpeg.ps1', rebuild Windows, then create the installer."
}

if (-not $NsisPath) {
  $nsisCandidates = @(
    (Join-Path $workspaceDir "tools\nsis\makensis.exe"),
    "C:\Program Files (x86)\NSIS\makensis.exe",
    "C:\Program Files\NSIS\makensis.exe"
  )
  $NsisPath = $nsisCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
}

if (-not $NsisPath -or -not (Test-Path -LiteralPath $NsisPath)) {
  throw "makensis.exe was not found. Pass its path with -NsisPath."
}

if (-not $VcRedistPath) {
  $vcRedistCandidates = @(
    "C:\BuildTools\VC\Redist\MSVC\v143\vc_redist.x64.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\v143\vc_redist.x64.exe",
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Redist\MSVC\v143\vc_redist.x64.exe"
  )
  $VcRedistPath = $vcRedistCandidates |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
}

if (-not $VcRedistPath -or -not (Test-Path -LiteralPath $VcRedistPath)) {
  throw "vc_redist.x64.exe was not found. Pass its path with -VcRedistPath."
}

New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Push-Location $windowsDir
try {
  & $NsisPath `
    "/DAPP_VERSION=$Version" `
    "/DAPP_BUILD=$BuildNumber" `
    "/DVC_REDIST_PATH=$VcRedistPath" `
    $installerScript

  if ($LASTEXITCODE -ne 0) {
    throw "NSIS failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}

$installerPath = Join-Path $outputDir "Another-IPTV-Player-Setup-$Version.exe"
if (-not (Test-Path -LiteralPath $installerPath)) {
  throw "NSIS completed without creating the expected installer."
}

$programsDir = "E:\Onedrive\OneDrive - Yorg\OneDrive\Programs"
New-Item -ItemType Directory -Force -Path $programsDir | Out-Null
Copy-Item -LiteralPath $installerPath -Destination $programsDir -Force
Write-Host "Copied installer to $programsDir"

Get-Item -LiteralPath $installerPath
