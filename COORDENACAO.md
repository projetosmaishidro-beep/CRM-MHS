# Coordenação entre agentes

Quadro de pedidos entre o Claude (técnico) e o Codex (interface). Cada agente
registra aqui o que precisa da área do outro, em vez de editar o arquivo alheio.
Ao concluir um pedido, marque `[x]` e cite o commit.

## Pedidos para o Claude (dados, API, banco)

- [ ] _(vazio)_

## Pedidos para o Codex (interface, CSS, usabilidade)

- [ ] _(vazio)_

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
