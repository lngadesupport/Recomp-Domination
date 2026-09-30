# Recomp Domination

Bring-up de **recompilação estática nativa para Windows x64** de *Downhill Domination* (PS2, NTSC-U, `SCUS-97177`) usando o PS2Recomp atual.

> O repositório contém somente tooling, configuração e metadados derivados. Não versione o ELF retail, ISO, BIOS ou assets proprietários.

## Estrutura local esperada

O bootstrap foi preparado para a pasta que você já usa:

```text
D:\Recomp Domination\
├── SCUS_971.77
└── Recomp-Domination\
    ├── BUILD_DOWNHILL.cmd
    ├── scripts\
    └── src\
```

Também é possível informar outro diretório como primeiro argumento do `BUILD_DOWNHILL.cmd`.

## Build confirmada

O ELF alvo foi validado diretamente:

- tamanho: `1.691.684` bytes
- SHA-256: `ADFDA7B73A8F05FB20A3F0F318772E9D3797FD4D6C0A6C0078AE392DF0F0CF0C`
- ELF entry: `0x0010A008`
- machine: `EM_MIPS (8)`
- PCSX2 ELF CRC: `0x5AE01D98`
- único `PT_LOAD`: offset `0x1000`, vaddr `0x0010A000`, filesz `0x00193CF0`, memsz `0x00796400`, flags `RWX`

Anchors conferidos byte a byte no ELF:

| endereço | instrução | alvo/uso |
|---|---:|---|
| `0x0025C5A0` | `0x0C097110` | JAL → `0x0025C440` (`sceSifSendCmd`) |
| `0x0024520C` | `0x0C095014` | JAL → `0x00254050` (`scePadRead`) |
| `0x001B6740` | `0x0C07EDB0` | JAL → `0x001FB6C0` (`main`) |
| `0x00243D34` | `0x30420001` | anchor de vídeo/interlace |

## Requisitos

- Windows 10/11 x64
- Git
- CMake 3.21+
- Visual Studio 2022 ou Build Tools 2022 com **Desktop development with C++**
- internet na primeira sincronização do PS2Recomp; depois, o commit fixado pode ser reutilizado offline

## Preflight recomendado

Antes do primeiro build, rode:

```cmd
CHECK_ENVIRONMENT.cmd
```

Ele verifica Git, CMake, MSVC x64, o ELF validado, SHA-256, espaço livre e conectividade com GitHub, e grava `analysis\local\environment.json`.

## Um comando

Abra o repositório e execute:

```cmd
BUILD_DOWNHILL.cmd
```

Ou, se a pasta do jogo estiver em outro local:

```cmd
BUILD_DOWNHILL.cmd "D:\Minha Pasta do Jogo"
```

O bootstrap:

1. localiza e valida o `SCUS_971.77`;
2. clona o PS2Recomp;
3. fixa a revisão `75d729ce40d7eed9649fd4bb05628dee520f3d0c`;
4. compila `ps2_analyzer` e `ps2_recomp`;
5. roda o analyzer sobre o ELF real;
6. ajusta o TOML para a build do Downhill;
7. adiciona os bindings confirmados de `scePadRead` e `sceSifSendCmd`;
8. gera o C++ recompilado;
9. instala os headers gerados no runtime;
10. compila `ps2EntryRunner.exe` em Windows x64;
11. copia o executável para `D:\Recomp Domination\DownhillRecompiled\`.

O primeiro bring-up desativa FFmpeg e Debug UI para reduzir dependências, mas mantém logs e trace IOP/SIF ligados.

## Estado

O objetivo imediato é chegar a um executável nativo que percorra:

```text
ELF -> entry -> main -> SIF/IOP -> PAD -> VIF1/VU1 -> GIF/GS -> primeiro frame
```

A partir do primeiro bloqueio real de runtime, a implementação passa a ser iterativa e baseada em logs, sem emulação embutida.


## Fluxo recomendado

Na primeira preparação local:

```cmd
PREPARE_GAME_DATA.cmd
```

Esse comando é opcional. Ele procura `SYSTEM.CNF`, uma ISO local ou volumes multipart RAR. Se houver multipart RAR e 7-Zip disponível, os dados são extraídos localmente para `game_data` e o caminho correto é gravado em sidecars `downhill_cd_root.txt` / `downhill_cd_image.txt`. Nenhum dado proprietário é adicionado ao Git.

Para melhorar as fronteiras de função do retail, com Ghidra instalado:

```cmd
GENERATE_GHIDRA_MAP.cmd
```

O comando roda Ghidra headless, importa o `SCUS_971.77`, adapta de forma verificável o exporter fixado para receber os caminhos TOML/CSV por argumentos (sem diálogos interativos), executa o exporter do PS2Recomp e gera:

```text
analysis\SCUS_971.77.functions.csv
analysis\SCUS_971.77.ghidra.toml
```

Depois rode:

```cmd
BUILD_DOWNHILL.cmd
```

Se o CSV/TOML do Ghidra existirem, o build os reutiliza automaticamente. No `FULL_PIPELINE_DOWNHILL.cmd`, Ghidra é tentado apenas quando o mapa ainda não existe; se Ghidra não estiver instalado, o fluxo continua com `ps2_analyzer` como fallback.

Após o build, execute:

```text
D:\Recomp Domination\DownhillRecompiled\RUN_DOWNHILL.cmd
```

O primeiro boot gera automaticamente:

```text
first_boot_latest.log
first_boot_exit_code.txt
first_boot_triage.json
first_boot_suggestions.json
recompiled_report.json
build_report.json
```

`first_boot_suggestions.json` identifica PCs de função ausentes dentro do segmento executável validado e stubs PS2 ainda não implementados. As sugestões não alteram o TOML automaticamente.

Para empacotar apenas diagnósticos seguros:

```cmd
COLLECT_DIAGNOSTICS.cmd
```

O ZIP de diagnóstico exclui ELF, ISO, RAR e assets do jogo.

## One-click local pipeline

For the validated local layout at `D:\Recomp Domination`, the most complete path is:

```cmd
cd /d "D:\Recomp Domination\Recomp-Domination"
git checkout bootstrap/compiler
git pull
FULL_PIPELINE_DOWNHILL.cmd
```

`FULL_PIPELINE_DOWNHILL.cmd` performs, in order:

1. environment preflight (Git, CMake, MSVC, ELF identity, disk space and PS2Recomp source availability);
2. game-data preparation / multipart RAR normalization and extraction;
3. optional Ghidra headless function-map generation or reuse, with analyzer fallback;
4. exact ELF identity, SHA-256, PT_LOAD and anchor validation;
5. deep R5900/COP/VU/MMI census;
6. pinned PS2Recomp analyzer/recompiler build;
7. static recompilation to generated C++ with conservative patch policy;
8. native Windows x64 runner build;
9. bounded 90-second first-boot probe plus milestone triage/suggestions;
10. non-proprietary diagnostics ZIP collection.

The 90-second probe timeout is diagnostic, not a game timeout. `RUN_DOWNHILL.cmd` remains available for unrestricted interactive runs.


## Build MPEG/FFmpeg opcional

O baseline continua com FFmpeg desativado para reduzir dependencias e acelerar o primeiro bring-up. Se o triage classificar o bloqueio como `mpeg-no-ffmpeg`, use:

```cmd
BUILD_DOWNHILL_FFMPEG.cmd
```

Esse modo ativa `PS2X_ENABLE_FFMPEG=ON` no runtime fixado do PS2Recomp. No Windows, o proprio CMake baixa o pacote prebuilt suportado e coloca as DLLs de FFmpeg ao lado de `ps2EntryRunner.exe`. O `build_report.json` registra `runtime_features.ffmpeg=true`.

Use esse modo para validar intro/PSS/MPEG real. Ele nao altera entry points, stubs, patches ou a identidade do ELF e nao substitui o build baseline.

## Bring-up iterativo opcional

Depois de obter um primeiro probe real, existe um modo opcional para iterar apenas sobre funções guest faltantes:

```cmd
AUTO_BRINGUP.cmd
```

Ele executa ciclos limitados de `build -> probe -> triage -> rebuild`. O modo não ativa patches, não transforma stubs TODO em HLE e não aceita endereços arbitrários. Novos entry points só são aceitos quando o triage primário é exatamente `missing-function`, o PC está alinhado a 4 bytes, está dentro do intervalo file-backed validado `0x0010A000..0x0029DCF0` e ainda não está configurado. Qualquer outra classificação — IOP/RPC, MPEG, VIF/VU/GS, TODO stub, crash ou instrução não suportada — bloqueia a expansão automática.

O padrão é no máximo 3 iterações. Antes de alterar `config\downhill.extra_entry_points.local.txt`, o script cria backup local. O relatório de cada sessão é salvo em `analysis\local\auto_bringup_*.json`.

Esse modo é para acelerar missing-function bring-up. Se o bloqueio real for IOP/SIF, VIF/VU/GS, instrução não suportada ou crash, ele interrompe a expansão de entry points em vez de mascarar o problema.

## Rebuild offline

Depois que `third_party\PS2Recomp` já contém o commit fixado
`75d729ce40d7eed9649fd4bb05628dee520f3d0c`, o build e o preflight não exigem
novo `git fetch`. Isso deixa os ciclos de bring-up `log -> ajuste -> rebuild`
funcionando sem rede, desde que as dependências CMake já estejam disponíveis no cache local.
