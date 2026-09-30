param([Parameter(Mandatory=$true)][string]$GameRoot, [Parameter(Mandatory=$true)][string]$ToolRoot, [switch]$RunProbe)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$RepoRoot = Split-Path $PSScriptRoot -Parent
$ToolRoot = (Resolve-Path -LiteralPath $ToolRoot).Path
$env:RECOMP_PORTABLE_TOOL_ROOT = $ToolRoot
$SourceRoot = Join-Path (Split-Path $ToolRoot -Parent) 'sources'
. (Join-Path $PSScriptRoot 'offline_sources.ps1')
$null = Get-OfflineCmakeArgs -SourceRoot $SourceRoot
$upstream = Join-Path $SourceRoot 'PS2Recomp'
if (!(Test-Path -LiteralPath (Join-Path $upstream '.git'))) { throw 'Fontes offline ausentes. Extraia o pacote completo, incluindo sources.' }
$destination = Join-Path $RepoRoot 'third_party/PS2Recomp'
New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
Copy-Item -LiteralPath $upstream -Destination $destination -Recurse -Force
$env:RECOMP_OFFLINE_SOURCE_ROOT = $SourceRoot
$env:CMAKE_GENERATOR = 'Ninja'
$env:CMAKE_BUILD_PARALLEL_LEVEL = [string][Math]::Max(1, [Math]::Min(4, [Environment]::ProcessorCount))
$bins = @('llvm\bin','cmake\bin','ninja','git\cmd','git\mingw64\bin') | ForEach-Object { Join-Path $ToolRoot $_ }
$env:Path = ($bins -join ';') + ';' + $env:Path
foreach ($exe in @('clang.exe','clang++.exe','cmake.exe','ninja.exe','git.exe')) {
    if (!(Get-Command $exe -ErrorAction SilentlyContinue)) { throw "Ferramenta portátil ausente: $exe. Extraia o ZIP inteiro, mantendo a pasta tools." }
}
Write-Host 'Modo portátil offline: ferramentas, fontes e dependências incluídos. Nenhum download durante a recompilação.'
$result = 1
try {
    if ($RunProbe) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\test_downhill_windows.ps1') -GameRoot $GameRoot -TimeoutSeconds 90
        $result = $LASTEXITCODE
    } else {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\prepare_game_data.ps1') -GameRoot $GameRoot
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao preparar dados. Use uma ISO ou os arquivos extraídos do disco; RAR requer extração prévia nesta versão portátil.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\build_downhill.ps1') -GameRoot $GameRoot -MultiFileOutput
        $result = $LASTEXITCODE
    }
} catch { Write-Host ('ERRO: ' + $_.Exception.Message); $result = 1 }
finally { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\collect_diagnostics.ps1') -GameRoot $GameRoot }
exit $result
