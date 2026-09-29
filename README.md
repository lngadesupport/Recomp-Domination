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
