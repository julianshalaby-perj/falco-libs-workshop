$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent $PSScriptRoot

function Invoke-LabMultipass {
    param([string[]] $CommandArgs)
    & multipass @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Multipass failed (exit $LASTEXITCODE): $($CommandArgs -join ' ')"
    }
}

if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    throw 'Install Multipass, then rerun setup: https://canonical.com/multipass/download/windows'
}

$Instances = Invoke-LabMultipass -CommandArgs @('list', '--format', 'json') | ConvertFrom-Json
if ($Instances.list.name -contains 'falco-lab') {
    Invoke-LabMultipass -CommandArgs @('start', 'falco-lab')
} else {
    Invoke-LabMultipass -CommandArgs @(
        'launch', '24.04', '--name', 'falco-lab', '--cpus', '4', '--memory', '8G', '--disk', '30G'
    )
}
Invoke-LabMultipass -CommandArgs @('exec', 'falco-lab', '--', 'mkdir', '-p', '/home/ubuntu/falco-libs-workshop')

# Keep attendees' source edits when setup is run again.
& multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/src/main.cpp
if ($LASTEXITCODE -ne 0) {
    Invoke-LabMultipass -CommandArgs @(
        'transfer', '--recursive', (Join-Path $WorkshopRoot 'src'),
        'falco-lab:/home/ubuntu/falco-libs-workshop/'
    )
}
Invoke-LabMultipass -CommandArgs @(
    'transfer', '--recursive', (Join-Path $WorkshopRoot 'scripts'),
    (Join-Path $WorkshopRoot 'FALCO_LIBS_REF'), 'falco-lab:/home/ubuntu/falco-libs-workshop/'
)
Invoke-LabMultipass -CommandArgs @('exec', 'falco-lab', '--', 'bash', '/home/ubuntu/falco-libs-workshop/scripts/setup.sh')
Write-Host 'Enter the workshop VM: multipass shell falco-lab'
