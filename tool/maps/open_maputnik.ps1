[CmdletBinding()]
param(
  [string]$StylePath = (Join-Path $PSScriptRoot '..\..\assets\maps\styles\blue_green_light.json'),
  [int]$Port = 8888
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
  throw 'Node.js/npm is required to run Maputnik through npx. Install Node.js, then rerun this task.'
}

if (-not (Test-Path $StylePath)) {
  throw "Style file not found: $StylePath"
}

$styleFullPath = (Resolve-Path $StylePath).Path
Write-Host "Opening Maputnik for $styleFullPath"
Write-Host 'Start the tile server first so Maputnik can read http://localhost:8080/data/nuuk/{z}/{x}/{y}.pbf.'

& npx --yes maputnik `
  --watch `
  --file "$styleFullPath" `
  --port $Port

if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}