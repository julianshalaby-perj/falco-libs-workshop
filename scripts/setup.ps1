$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent $PSScriptRoot

function Invoke-LabMultipass {
    param([string[]] $CommandArgs)
    & multipass @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Multipass failed (exit $LASTEXITCODE): $($CommandArgs -join ' ')"
    }
}

$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    $InstallAnswer = Read-Host 'Multipass is missing. Download and install it from Canonical? [y/N]'
    if ($InstallAnswer -notmatch '^(y|yes)$') {
        Write-Host 'Setup stopped. Multipass was not installed.'
        exit 1
    }
    $InstallerDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $InstallerDir | Out-Null
    try {
        $InstallerPath = Join-Path $InstallerDir 'multipass.msi'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri `
            'https://github.com/canonical/multipass/releases/download/v1.16.4/multipass-1.16.4%2Bwin-win64.msi' `
            -OutFile $InstallerPath
        $ExpectedHash = 'b0c417fb8254fa61e4aa63895f59354bb3717c58100816651a9300dd98124aea'
        if ((Get-FileHash -Algorithm SHA256 $InstallerPath).Hash -ne $ExpectedHash) {
            throw 'Multipass installer checksum did not match. Installation stopped.'
        }
        $Installer = Start-Process msiexec.exe -Verb RunAs -Wait -PassThru `
            -ArgumentList "/i `"$InstallerPath`" /norestart"
        if ($Installer.ExitCode -in @(3010, 1641)) {
            Write-Host 'Multipass installed. Restart Windows, then rerun this setup command.'
            exit 0
        }
        if ($Installer.ExitCode -ne 0) {
            throw "Multipass installation stopped (exit $($Installer.ExitCode))."
        }
    } finally {
        Remove-Item -Recurse -Force $InstallerDir
    }
    $env:Path += ";$MultipassBin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
        throw 'Multipass CLI is unavailable. Reopen PowerShell and rerun setup.'
    }
}

# Allow the newly installed daemon to start before creating the VM.
try {
    $ErrorActionPreference = 'Continue'
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        & multipass list *> $null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 2
    }
} finally {
    $ErrorActionPreference = 'Stop'
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
