# Testes com progressão automática

`scripts/run_progressive_tests.py` executa regressões Python, aplica os patches ao runtime fixado e compila um executável pequeno que exercita dois componentes reais: `downhill::leafHandler` e `ps2x::iop::lookupIsoFile`. O executável não contém o jogo recompilado, não exige assets e não testa DMA/VIF/GS completo.

Cada lote só começa se o anterior terminar corretamente, com a quantidade, semente, intervalo de casos e famílias esperadas. Uma falha, timeout, limite de log ou esgotamento do orçamento interrompe a progressão. O relatório `progress.json` é atualizado após cada etapa. Uma pasta de saída existente é recusada para preservar a execução anterior.

| Etapa | Casos padrão | Complexidade |
|---|---:|---|
| Regressões Python | Contagem verificada pelo unittest | Watchdog, identidade, diagnóstico e critérios de FPS |
| Lote inicial | 1.000 | Diretório raiz; cópias pequenas; retorno, transferência e exceção |
| Lote ampliado | 9.000 | Um diretório; comprimentos/alinhamentos variados |
| Lote de stress | 90.000 | Três diretórios; novos IDs e dados |
| Boot observado | Uma execução limitada, se configurada | Identidade do ELF/runner, início do guest, logs de fila |
| Menu, corrida e desempenho | Bloqueados atualmente | Exigem roteiros, inventário e telemetria validáveis |

`--cases 1000000` usa lotes de 1.000, 9.000 e 990.000 casos, sem repetir IDs dentro da campanha. Metade dos casos exercita o adapter de handlers; a outra metade, a busca no disco. A contagem não representa um milhão de funções diferentes: há três modos de handler e doze classes de fixtures ISO, com entradas parametrizadas.

Os casos verificam o PC de retorno antes da chamada, preservação de transferências/exceções, registros e bytes de guarda; na busca ISO, verificam extents/tamanhos esperados, caminhos normalizados, arquivo inexistente, traversal, descritor/registro inválido, leitura incompleta e rejeição de XAR/multi-extent. As expectativas vêm da construção independente das fixtures.

## Executar componentes

É necessário Python 3.10+, Git, o checkout PS2Recomp fixado pelo projeto e um compilador C++20 com AVX2. Não há download automático de dependências.

Linux, com AddressSanitizer e UndefinedBehaviorSanitizer:

```bash
python3 scripts/run_progressive_tests.py --out analysis/local/progressive-001 --cases 1000000 --sanitize --components-only
```

Windows, em um terminal x64 do Visual Studio/Build Tools:

```powershell
python scripts/run_progressive_tests.py --out analysis/local/progressive-001 --cases 1000000 --components-only
```

`--seed 0xD0A12` escolhe outra campanha reproduzível. `--budget-seconds 600` define o orçamento total; cada subprocesso também tem um limite. O executável recebe `COUNT SEED FIRST LEVEL`; para reproduzir um caso isolado, use `COUNT=1` e o ID da falha como `FIRST`, mantendo semente e nível. O relatório preserva o comando de cada lote e hashes dos componentes/executável.

O modo `--sanitize` verifica acesso à memória e comportamento indefinido. Detecção de vazamentos fica desabilitada, pois alguns ambientes gerenciados não permitem a enumeração de tarefas exigida pelo LeakSanitizer. Não se declara cobertura de vazamentos.

## Avançar ao jogo

Com runner, ELF e dados disponíveis:

```powershell
python scripts/run_progressive_tests.py --out analysis/local/progressive-retail-001 --runner "D:/Recomp Domination/DownhillRecompiled/ps2EntryRunner.exe" --elf "D:/Recomp Domination/SCUS_971.77" --cd-root "D:/Recomp Domination/disc-verified" --cd-image "D:/Recomp Domination/downhill-verified-probe.iso" --probe-seconds 240
```

O processo usa uma cópia isolada do runner/ELF e dos DLLs adjacentes, registra os caminhos do disco na pasta de teste e não altera a instalação original. No Linux é necessário um display gráfico configurado. `--experimental-boot` ativa explicitamente os dois workarounds de VSync/read-yield já existentes; por padrão permanecem desligados. O diagnóstico de fila fica ativo no probe.

Também é possível exercitar a classificação com uma captura anterior:

```bash
python3 scripts/run_progressive_tests.py --out analysis/local/progressive-evidence-001 --historical-probe analysis/evidence/2026-10-01-vif1-queue
```

Esse modo registra **observação histórica**, não um novo boot. A captura existente mostra a VIF1 ociosa, com flags de fila `0,3,1` e PC `0x1B4648`; a suíte mantém o menu bloqueado. Conclusões mascaradas e flags pendentes são observações, não uma prova completa da causa.

O processo retorna `0` quando o escopo solicitado passa, `1` em falha e `2` em bloqueio. `--components-only` pode passar sem o jogo; o modo completo atual retorna `2` no gate do menu. Não existe ainda um controlador que percorra menus/pistas sozinho. Esses estágios exigem roteiros e critérios de conclusão reais, e não avançam por mensagens genéricas no log.

## Critérios de 60/75 FPS

`scripts/evaluate_frame_times.py` avalia um CSV de quadros únicos do guest apresentados: `present_ns,guest_frame_id,scenario,phase`. `phase` deve ser `menu` ou `race`; uma captura contém apenas um cenário/fase. O produtor dessa telemetria ainda precisa ser integrado e validado no jogo.

```bash
python3 scripts/evaluate_frame_times.py corrida.csv
```

A política exige pelo menos 60 segundos e verifica todos os intervalos, com orçamento de 16.666.667 ns para 60 FPS e 13.333.334 ns para 75 FPS. Um pico além do orçamento, quadro perdido, repetido ou fora de ordem impede aprovação. A média sozinha não aprova estabilidade. O avaliador não aceita contadores de host como telemetria de gameplay nem declara cobertura do jogo inteiro.

Os dados sintéticos usados nas regressões do avaliador testam os critérios; não são medições de desempenho do jogo.

## Verificação contínua

O workflow `Runtime recovery checks` executa automaticamente 100 mil casos em Ubuntu (ASan/UBSan) e Windows (MSVC) em commits das branches `bringup/**`. Os logs mostram cada etapa. Os mesmos IDs/semente em plataformas diferentes são execuções adicionais dos casos; não são somados como novos casos distintos.

## COP0 and VIF1 pipeline regressions

See [COP0 condition evidence](../analysis/cop0_condition_2026-10-01.md) for the exhaustive production-code-generation test (5,242,880 executions, 1,048,576 channel states), likely delay slots and opt-in 64-command VIF1 history. These counts are separate from the earlier ISO/leaf-handler campaign. The dedicated `cop0-condition-ci.yml` repeats the regression on Linux and Windows. Neither campaign proves full-game FPS.
