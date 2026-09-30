# Recomp Domination portátil — Windows x64

Extraia TODO o ZIP em uma pasta. Mantenha `RecompDomination.exe`, `tools` e `sources` juntos.
Abra o aplicativo, selecione a pasta com `SCUS_971.77` e os dados do disco e clique em **Recompilar e testar**.

Não instala Git, CMake, Visual Studio nem altera o PATH permanente. As ferramentas incluídas são LLVM-MinGW, CMake, Ninja e MinGit, com suas licenças originais.
Usa Windows PowerShell e .NET Framework do Windows. A CPU deve suportar AVX2.
A recompilação funciona offline desde o primeiro build: fontes e dependências estão incluídos e os downloads são bloqueados. Reserve vários GB livres e tempo para compilar milhares de funções.

Use os dados extraídos do disco com SYSTEM.CNF e MOD, ou uma ISO ao lado do ELF. RAR multipart deve ser extraído antes neste pacote.
O executável gerado fica em `DownhillRecompiled` dentro da pasta do jogo; os diagnósticos ficam em `RecompDomination_Diagnostics_*.zip`.

O teste termina após 90 segundos. Um timeout não confirma que menu ou corrida funcionam. A versão portátil muda o compilador nativo para Clang; o boot real precisa de validação no seu PC.
