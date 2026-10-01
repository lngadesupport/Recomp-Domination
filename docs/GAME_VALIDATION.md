# Validação de menus e corridas

O teste de boot e a compilação são etapas iniciais. Um timeout sem crash, uma janela aberta ou contadores gráficos não validam o jogo completo.

## Estado atual

| Etapa | Evidência atual | Resultado |
|---|---|---|
| Recompilação | ELF identificado e código gerado | Verificada |
| Runtime local | Executável Linux vinculado | Verificado |
| Inicialização IOP | Nove IRX físicos carregados | Observada |
| Busca no DVD | DHSKAT.SKX lido; 2.335 arquivos conferidos por CRC e ISO reconstruída validada | Verificada na imagem de teste |
| Comandos gráficos | DMA/VIF/GIF e dois registros GS | Observados |
| Vídeos de abertura | Capturas aos 30, 90 e 175 segundos mostram Sony, direitos autorais e Incog | Observados no runtime Linux com FFmpeg |
| Carregamento após trailer | Retorno de memcpy corrigido; workers avançam com as opções experimentais de boot | Carregamento ainda não conclui |
| Primeiro menu | Thread principal aguarda fila gráfica/VIF1; imagem corrompida, sem menu utilizável | Não validado |
| Todos os menus | Depende do primeiro menu e dos dados completos | Não executado |
| Todas as corridas | Inventário completo de pistas/modos ainda indisponível | Não executado |

Registro técnico desta retomada: [recuperação e testes de 01/10](../analysis/retail_recovery_2026-10-01.md). A meta de 120 FPS ainda não foi validada em corrida.

## Como comprovar a cobertura completa

1. Identificar a edição do jogo e conferir a integridade dos dados do disco. Catalogar todos os menus, pistas, variantes, modos, personagens e estados de desbloqueio da edição. O inventário deve ser fechado antes de calcular qualquer porcentagem de cobertura.
2. Registrar um caso separado para cada fluxo: entrada, seleção, confirmação, cancelamento e retorno. Incluir opções de vídeo, áudio e controle, seleção de personagem/pista, pausa, resultados e salvar/carregar onde existirem.
3. Para cada corrida disponível, exercitar carregamento, largada, percurso completo, adversários, colisões, chegada, resultados, reinício e retorno ao menu. Cobrir variantes e modos, inclusive multiplayer quando presente, em casos próprios.
4. Reproduzir sequências de entrada e pontos de captura equivalentes no original e no recompilado. Comparar conteúdo da tela, estados, áudio e comportamento; o alvo não é uma imagem idêntica em resolução diferente.
5. Guardar por execução: versão do recompilador/runtime, hashes do ELF e do executável, configuração, entradas usadas, log, capturas e resultado das verificações. Separar explicitamente passou, falhou, bloqueado e não executado.
6. Repetir os casos depois de mudanças em SIF/IOP, memória, DMA/VIF/GS, controles, áudio e salvamento. Uma correção de boot pode causar regressões em outros caminhos.

Só declarar cobertura completa quando o inventário estiver fechado e cada caso tiver evidência de conclusão. Atualmente não existe evidência para aprovar menus ou corridas.

Resource processing diagnostics: enable `PS2_TRACE_RESOURCE_COPY=1` for bounded
executor-side observations at return `0x240BB4`, then run
`python scripts/analyze_resource_copy_trace.py <runtime.log>`.
The flag preserves the existing memcpy handler and is off by default. The copy
source is a dictionary/back-reference buffer, not necessarily compressed disc
input. Zero lengths, offsets and sampled bytes alone do not establish a stall.
This instrumentation has compile/parser validation only; a new retail probe is
still required.
