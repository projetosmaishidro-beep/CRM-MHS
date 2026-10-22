# Coordenação entre agentes

Quadro de pedidos entre o Claude (técnico) e o Codex (interface). Cada agente
registra aqui o que precisa da área do outro, em vez de editar o arquivo alheio.
Ao concluir um pedido, marque `[x]` e cite o commit.

## Pedidos para o Claude (dados, API, banco)

- [ ] **Auditoria de segurança — parte 2 (complemento da migration 0057).**
  Trabalhar na worktree `claude-backend` (branch `backend/claude`), com os
  MCPs `supabase-central`/`supabase-central-admin`. A 0057 só validou policies
  de SELECT em cadastro, crm, mapa e propostas_mhs. Verificar no banco real e
  **mostrar ao usuário antes de alterar**:
  1. Policies com cmd ALL/INSERT/UPDATE/DELETE em qualquer schema da aplicação
     com using/with check `true` ou sem eh_editor/eh_admin/eh_membro (em
     especial "Equipe pode gerenciar despesas/eventos/participantes").
  2. Schema `mapa_clientes` (existe? exposto na API? `base_mapa_anon_select`
     ainda existe? anon tem SELECT?), além de core, integracao e public.
  3. Policies de SELECT em storage.objects e buckets públicos.
  4. Grants de tabela para anon em todos os schemas da aplicação.
  Se houver exposição: migration 0058 corrigindo e ampliando a validação para
  cmd ALL e todos os schemas; rodar advisors; commitar na backend/claude.
- [ ] **Confirmar quais versões das RPCs de escrita estão ativas no banco.**
  `banco_simples/08_conexao_apps/09_api_escrita_crm.sql` e
  `08_api_escrita_eventos.sql` redefinem `criar_visita`, `atualizar_viagem`,
  `criar_despesa`, `atualizar_despesa` e `atualizar_evento` lendo menos campos
  que as migrations 0002/0003. Se forem as ativas, descartam: viagem, tipo,
  localização e anexos da visita; paradas, odômetro, notas e anexos da viagem;
  centro de custo da despesa; anexos e notas do evento. Comparar com
  `pg_get_functiondef` e, se preciso, migration restaurando a versão completa.
- [ ] **Conferir `max rows` do PostgREST no projeto.** O `api.js` já pagina
  qualquer limite (testado com 1000, 500 e sem limite), mas o valor real define
  quantas requisições cada carga faz.
- [ ] **Reduzir o que a primeira carga baixa.** Com 10 mil clientes e 40 mil
  visitas o retrato completo tem ~34 MB: a primeira abertura leva ~29 s em 4G
  (as seguintes ~0,5 s, pelo cache). Próximo passo: views enxutas por tela
  (só as colunas usadas) e agregados no banco (contagens e somas por viagem,
  cliente e usuário) em vez de baixar todas as linhas.
- [ ] **XSS armazenado.** Vários templates das telas interpolam textos do banco
  (nome de cliente, observações, notas) sem `UI.escape`. Um nome com `<script>`
  ou `<img onerror>` executaria no navegador de quem abrir a tela. Já escapados:
  `trips.js`, `visits.js` e "Últimos registros" do painel. Levantar os demais
  junto com o Codex.

## Pedidos para o Codex (interface, CSS, usabilidade)

- [ ] **Valor grande no cartão "Gastos em viagens" (painel, celular).** Valores
  como "R$ 3.766.485,98" ficam sob o ícone decorativo do cartão.
- [ ] **Revisar o visual de três elementos novos** (criados pelo Claude com
  classes existentes, sem CSS novo): botão "Mostrar mais" em `trips.js`
  (`.trips-more`), campo de busca de clientes no diálogo "Nova viagem"
  (`#tripClientSearch`) e estado vazio de "Últimos registros" no painel.

## Mudanças de contrato anunciadas

Alterações no formato dos objetos do `Store` ou nas funções `UI.*Supabase*`.

- **2026-10-20 — camada de dados extraída para `assets/js/api.js`** (branch
  `backend/claude`). Nomes e assinaturas de `UI.*Supabase*`,
  `UI.hydrateSupabaseSnapshot` e `UI.uploadPrivateFile` não mudaram. Foram
  removidas funções legadas sem uso: `UI.hydrateRemoteClients`,
  `UI.createRemoteTrip`, `UI.hydrateRemoteEvents`, `UI.saveRemoteEvent`,
  `UI.saveRemoteExpense`, `UI.uploadToStorage`, `UI.updateRemoteEventMedia`,
  `UI.deleteRemoteExpense`, `UI.updateRemoteExpense`, `UI.updateRemoteEvent`.
  Todos os HTMLs passaram a carregar `api.js` antes de `ui.js`.
- **2026-10-22 — carga, cache e índices** (branch `backend/claude`).
  - `Store.byId(colecao)` e `Store.groupBy(colecao, campo)`: índices em
    memória, recalculados quando o estado muda. Use-os em vez de
    `state.x.filter/find` dentro de laços.
  - `state.activities` agora vem preenchido (últimas visitas, despesas e
    viagens: `{ id, userId, date, text }`).
  - O retrato fica em cache local (IndexedDB) por até 12 h e é reaproveitado
    sem rede por 2 min; escritas invalidam o cache. Evento
    `api:snapshot-updated` avisa quando há dados novos em segundo plano. O
    `Store` da tela aberta nunca é trocado em segundo plano.
  - Telas alteradas pelo Claude nesta rodada (desempenho e correções de dados,
    sem mudar classes): `trips.js` (lista paginada e busca de clientes no
    diálogo), `visits.js` (ordenação única, mapa limitado a 500 pontos),
    `reports.js`, `trip.js`, `user.js`, `users.js`, `events.js` (índices),
    `dashboard.js` (atividades), `event.js` e `new-visit.js` (payloads), e o
    handler de logout em `ui.js`. Faça `git merge main` antes de editá-las.
