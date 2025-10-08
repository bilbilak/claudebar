# Regenerate translation files for the Windows .NET app and the WiX
# installer from /i18n/strings.yaml.
#
# Usage (from anywhere):
#   pwsh apps/windows/i18n.ps1
#
# Requires: python3 with PyYAML on PATH.
#
# Idempotent — re-running with the same YAML produces byte-identical output.

$ErrorActionPreference = 'Stop'

# Resolve repo root from this script's location (apps/windows/i18n.ps1).
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir '..' '..')

Push-Location $repoRoot
try {
    Write-Host "[i18n] Regenerating .resx files for the .NET app..." -ForegroundColor Cyan
    python3 scripts/regenerate-translations.py windows
    if ($LASTEXITCODE -ne 0) { throw "windows regen failed (exit $LASTEXITCODE)" }

    Write-Host "[i18n] Regenerating .wxl files for the WiX installer..." -ForegroundColor Cyan
    python3 scripts/regenerate-translations.py wix
    if ($LASTEXITCODE -ne 0) { throw "wix regen failed (exit $LASTEXITCODE)" }

    Write-Host "[i18n] Done." -ForegroundColor Green
}
finally {
    Pop-Location
}
