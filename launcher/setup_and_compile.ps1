param([Parameter(Mandatory=$true)][string]$GameRoot, [switch]$RunProbe)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path $PSScriptRoot -Parent
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Refresh-ToolPath {
    $paths = @([Environment]::GetEnvironmentVariable('Path','Machine'), [Environment]::GetEnvironmentVariable('Path','User'), $env:Path,
        (Join-Path $env:ProgramFiles 'Git\cmd'), (Join-Path $env:ProgramFiles 'CMake\bin'), (Join-Path $env:ProgramFiles '7-Zip'))
    $env:Path = $paths -join ';'
}
function Install-Package {
    param([string]$Id)
    if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'O instalador de aplicativos do Windows (App Installer/winget) está ausente. Instale-o pela Microsoft Store e abra o recompilador novamente: https://apps.microsoft.com/detail/9nblggh4nns1'
    }
    Write-Host "Instalando $Id..."
    & winget.exe install --id $Id --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) { throw "Instalação de $Id falhou: $LASTEXITCODE" }
    Refresh-ToolPath
}
function Find-Msvc {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path -LiteralPath $vswhere)) { return $null }
    $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -eq 0 -and $installation) { return $installation }
    return $null
}
$result = 1
try {
    Refresh-ToolPath
    if (!(Get-Command git.exe -ErrorAction SilentlyContinue)) { Install-Package 'Git.Git' }
    $msvc = Find-Msvc
    if (!$msvc) {
        Write-Host 'Baixando Microsoft Build Tools 2022 (C++). A instalação pode demorar.'
        $installer = Join-Path $PSScriptRoot 'vs_buildtools.exe'
        Invoke-WebRequest 'https://aka.ms/vs/17/release/vs_buildtools.exe' -OutFile $installer -UseBasicParsing
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Assinatura Microsoft do instalador não foi validada.' }
        $process = Start-Process -FilePath $installer -Verb RunAs -ArgumentList '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' -Wait -PassThru
        if ($process.ExitCode -eq 3010) { throw 'As ferramentas foram instaladas. Reinicie o Windows e abra o recompilador novamente.' }
        if ($process.ExitCode -ne 0) { throw "Instalação C++ falhou: $($process.ExitCode)" }
        $msvc = Find-Msvc
        if (!$msvc) { throw 'A instalação terminou sem disponibilizar MSVC x64.' }
    }
    $bundledCmake = Join-Path $msvc 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
    $env:Path = $bundledCmake + ';' + $env:Path
    if (!(Get-Command cmake.exe -ErrorAction SilentlyContinue)) { Install-Package 'Kitware.CMake' }
    if (@(Get-ChildItem -LiteralPath $GameRoot -Filter '*.rar' -File).Count -gt 0 -and !(Get-Command 7z.exe -ErrorAction SilentlyContinue)) { Install-Package '7zip.7zip' }
    Write-Host 'Ferramentas prontas. Preparando os dados do jogo...'
    if ($RunProbe) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\test_downhill_windows.ps1') -GameRoot $GameRoot -TimeoutSeconds 90
        $result = $LASTEXITCODE
        if ($result -eq 124) { Write-Host 'Teste encerrado pelo watchdog. O ZIP contém o diagnóstico do boot.' }
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\prepare_game_data.ps1') -GameRoot $GameRoot
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar os dados do disco.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\build_downhill.ps1') -GameRoot $GameRoot -MultiFileOutput
        $result = $LASTEXITCODE
    }
} catch { Write-Host ('ERRO: ' + $_.Exception.Message); $result = 1 }
finally {
    try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\collect_diagnostics.ps1') -GameRoot $GameRoot } catch { Write-Warning $_.Exception.Message }
}
exit $result
