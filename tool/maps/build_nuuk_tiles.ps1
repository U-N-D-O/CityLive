[CmdletBinding()]
param(
  [string]$PbfPath = (Join-Path $PSScriptRoot '..\..\greenland-260810.osm.pbf'),
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\..\build\maps\nuuk.mbtiles'),
  [string]$Bounds = '-51.86,64.10,-51.57,64.25',
  [string]$PlanetilerImage = 'ghcr.io/onthegomap/planetiler:latest'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker is required to build vector tiles. Install Docker Desktop, then rerun this task.'
}

if (-not (Test-Path $PbfPath)) {
  throw "PBF file not found: $PbfPath"
}

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pbfFullPath = (Resolve-Path $PbfPath).Path
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not $pbfFullPath.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'The PBF file must be inside the workspace so it can be mounted into Docker.'
}

if (-not $outputFullPath.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'The output path must be inside the workspace so it can be mounted into Docker.'
}

$outputDir = Split-Path -Parent $outputFullPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

$relativePbf = $pbfFullPath.Substring($workspaceRoot.Length).TrimStart('\') -replace '\', '/'
$relativeOutput = $outputFullPath.Substring($workspaceRoot.Length).TrimStart('\') -replace '\', '/'

Write-Host "Building Nuuk vector tiles from $relativePbf"
Write-Host "Bounds: $Bounds"
Write-Host "Output: $relativeOutput"

& docker run --rm `
  -v "${workspaceRoot}:/data" `
  $PlanetilerImage `
  "--osm-path=/data/$relativePbf" `
  "--output=/data/$relativeOutput" `
  "--bounds=$Bounds" `
  --download `
  --force

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

Write-Host "Created $outputFullPath"