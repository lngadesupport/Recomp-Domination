# Validação de menus e corridas

O teste de boot e a compilação são etapas iniciais. Um timeout sem crash, uma janela aberta ou contadores gráficos não validam o jogo completo.

## Estado atual

| Etapa | Evidência atual | Resultado |
|---|---|---|
| Recompilação | ELF identificado e código gerado | Verificada |
| Runtime local | Executável Linux vinculado | Verificado |
| Inicialização IOP | Nove IRX físicos carregados | Observada |
| Busca no DVD | A chamada saiu da espera RPC e buscou DHSKAT.SKX | Handler exercitado; arquivo ausente |
| Comandos gráficos | DMA/VIF/GIF e dois registros GS | Observados |
| Primeiro menu | Framebuffer permanece na textura inicial do runtime | Não validado |
| Todos os menus | Depende do primeiro menu e dos dados completos | Não executado |
| Todas as corridas | Inventário completo de pistas/modos ainda indisponível | Não executado |

## Como comprovar a cobertura completa

1. Identificar a edição do jogo e conferir a integridade dos dados do disco. Catalogar todos os menus, pistas, variantes, modos, personagens e estados de desbloqueio da edição. O inventário deve ser fechado antes de calcular qualquer porcentagem de cobertura.
2. Registrar um caso separado para cada fluxo: entrada, seleção, confirmação, cancelamento e retorno. Incluir opções de vídeo, áudio e controle, seleção de personagem/pista, pausa, resultados e salvar/carregar onde existirem.
3. Para cada corrida disponível, exercitar carregamento, largada, percurso completo, adversários, colisões, chegada, resultados, reinício e retorno ao menu. Cobrir variantes e modos, inclusive multiplayer quando presente, em casos próprios.
4. Reproduzir sequências de entrada e pontos de captura equivalentes no original e no recompilado. Comparar conteúdo da tela, estados, áudio e comportamento; o alvo não é uma imagem idêntica em resolução diferente.
5. Guardar por execução: versão do recompilador/runtime, hashes do ELF e do executável, configuração, entradas usadas, log, capturas e resultado das verificações. Separar explicitamente passou, falhou, bloqueado e não executado.
6. Repetir os casos depois de mudanças em SIF/IOP, memória, DMA/VIF/GS, controles, áudio e salvamento. Uma correção de boot pode causar regressões em outros caminhos.

Só declarar cobertura completa quando o inventário estiver fechado e cada caso tiver evidência de conclusão. Atualmente não existe evidência para aprovar menus ou corridas.
