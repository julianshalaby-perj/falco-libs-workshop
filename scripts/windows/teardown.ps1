$ErrorActionPreference = 'Stop'
$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    Write-Host 'Multipass is not installed. Nothing to tear down.'
    exit 0
}
try {
    # Check the daemon first so a connection failure is not mistaken for no VM.
    $Instances = & multipass list --format csv
    if ($LASTEXITCODE -ne 0) { throw 'Could not contact Multipass. Teardown did not run.' }
    $Lab = $Instances | ConvertFrom-Csv | Where-Object { $_.Name -eq 'falco-lab' }
    if (-not $Lab) {
        Write-Host 'No falco-lab VM exists. Nothing to tear down.'
        exit 0
    }

    Write-Host 'This permanently deletes the falco-lab VM and everything inside it.'
    Write-Host 'Your local source and logs, other VMs, and Multipass installation stay.'
    $Answer = Read-Host 'Delete falco-lab? [y/N]'
    if ($Answer -notmatch '^(y|yes)$') {
        Write-Host 'Cancelled. The VM is unchanged.'
        exit 0
    }
    # Purge only this named VM. Never use the global multipass purge command.
    & multipass delete --purge falco-lab
    if ($LASTEXITCODE -ne 0) { throw 'Could not delete falco-lab. Check the Multipass error above.' }
    Write-Host 'Workshop VM and disk removed. Run setup again to recreate them.'
} catch {
    Write-Error $_
    exit 1
}
