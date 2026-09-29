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
- internet na primeira execução para dependências do PS2Recomp

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

Se o CSV do Ghidra existir, o build o usa automaticamente. Caso contrário, usa o `ps2_analyzer` como fallback de bring-up.

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

1. game-data preparation / multipart RAR normalization and extraction;
2. `SYSTEM.CNF` validation against `SCUS_971.77`;
3. exact ELF identity and anchor validation;
4. pinned PS2Recomp analyzer/recompiler build;
5. static recompilation to generated C++;
6. native Windows x64 runner build;
7. bounded 90-second first-boot probe;
8. triage/suggestion generation;
9. non-proprietary diagnostics ZIP collection.

The 90-second probe timeout is diagnostic, not a game timeout. `RUN_DOWNHILL.cmd` remains available for unrestricted interactive runs.
