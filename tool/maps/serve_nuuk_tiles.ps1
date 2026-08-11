[CmdletBinding()]
param(
  [string]$MbtilesPath = (Join-Path $PSScriptRoot '..\..\build\maps\nuuk.mbtiles'),
  [int]$Port = 8080,
  [string]$TileServerImage = 'maptiler/tileserver-gl:latest'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw 'Docker is required to serve vector tiles. Install Docker Desktop, then rerun this task.'
}

if (-not (Test-Path $MbtilesPath)) {
  throw "MBTiles file not found: $MbtilesPath. Run the 'Build Nuuk vector tiles from Greenland PBF' task first."
}

$mbtilesFullPath = (Resolve-Path $MbtilesPath).Path
$tileDir = Split-Path -Parent $mbtilesFullPath
$tileFile = Split-Path -Leaf $mbtilesFullPath

Write-Host "Serving $tileFile on http://localhost:$Port/data/nuuk/{z}/{x}/{y}.pbf"

& docker run --rm -it `
  -p "${Port}:8080" `
  -v "${tileDir}:/data" `
  $TileServerImage `
  --port 8080 `
  --mbtiles "/data/$tileFile"

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}