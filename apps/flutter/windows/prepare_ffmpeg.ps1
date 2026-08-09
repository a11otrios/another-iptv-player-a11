[CmdletBinding()]
param(
  [string]$Version = "8.1.2",
  [string]$Sha256 = "e25b682664025d49034c981afb4bae36238a40f29a3cc1c713ad9a8b5b3528f6",
  [string]$DownloadUrl,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$windowsDir = $PSScriptRoot
$projectDir = Split-Path -Parent $windowsDir
$workspaceDir = (Resolve-Path (Join-Path $projectDir "..\..")).Path
$downloadsDir = Join-Path $workspaceDir "tools\downloads"
$targetDir = Join-Path $workspaceDir "tools\ffmpeg"
$archiveName = "ffmpeg-$Version-essentials_build.7z"
$archivePath = Join-Path $downloadsDir $archiveName
$stagingDir = Join-Path $downloadsDir "ffmpeg-extract"
$ffmpegPath = Join-Path $targetDir "ffmpeg.exe"

if (-not $DownloadUrl) {
  $DownloadUrl = "https://www.gyan.dev/ffmpeg/builds/packages/$archiveName"
}

if ((Test-Path -LiteralPath $ffmpegPath) -and -not $Force) {
  & $ffmpegPath -version | Select-Object -First 1
  exit 0
}

New-Item -ItemType Directory -Force -Path $downloadsDir | Out-Null

$downloadRequired = -not (Test-Path -LiteralPath $archivePath)
if (-not $downloadRequired) {
  $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
  $downloadRequired = $actualHash -ne $Sha256.ToLowerInvariant()
}
if ($downloadRequired) {
  Invoke-WebRequest -UseBasicParsing -Uri $DownloadUrl -OutFile $archivePath
}

$actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $Sha256.ToLowerInvariant()) {
  throw "FFmpeg archive checksum mismatch. Expected $Sha256 but received $actualHash."
}

if (Test-Path -LiteralPath $stagingDir) {
  Remove-Item -LiteralPath $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
& tar.exe -xf $archivePath -C $stagingDir
if ($LASTEXITCODE -ne 0) {
  throw "Unable to extract $archiveName with tar.exe."
}

$extractedFfmpeg = Get-ChildItem -LiteralPath $stagingDir -Recurse -File -Filter "ffmpeg.exe" |
  Select-Object -First 1
if (-not $extractedFfmpeg) {
  throw "The verified archive did not contain ffmpeg.exe."
}
$extractedRoot = Split-Path -Parent (Split-Path -Parent $extractedFfmpeg.FullName)

if (Test-Path -LiteralPath $targetDir) {
  Remove-Item -LiteralPath $targetDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
Copy-Item -LiteralPath $extractedFfmpeg.FullName -Destination $ffmpegPath

foreach ($noticeName in @("LICENSE", "README.txt")) {
  $noticePath = Join-Path $extractedRoot $noticeName
  if (Test-Path -LiteralPath $noticePath) {
    Copy-Item -LiteralPath $noticePath -Destination (Join-Path $targetDir $noticeName)
  }
}
Copy-Item -LiteralPath (Join-Path $windowsDir "ffmpeg-NOTICE.txt") -Destination (Join-Path $targetDir "NOTICE.txt")

Remove-Item -LiteralPath $stagingDir -Recurse -Force
& $ffmpegPath -version | Select-Object -First 1
