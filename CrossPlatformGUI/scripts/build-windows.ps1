$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Project = Join-Path $Root 'EntraMailSendRbac.Gui/EntraMailSendRbac.Gui.csproj'
$Out = Join-Path $Root 'dist/windows-x64'

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET SDK wurde nicht gefunden. Bitte .NET 8 SDK oder neuer installieren.'
}

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
    throw 'PowerShell 7 wurde nicht gefunden. Bitte PowerShell 7.4 oder neuer installieren.'
}

Remove-Item $Out -Recurse -Force -ErrorAction SilentlyContinue

dotnet publish $Project `
    -c Release `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=false `
    -o $Out

Write-Host "Fertig: $Out" -ForegroundColor Green
