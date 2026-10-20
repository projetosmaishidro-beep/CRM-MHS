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
