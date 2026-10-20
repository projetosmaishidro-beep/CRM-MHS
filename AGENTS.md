# Regras para agentes — Central Comercial (CRM MHS)

Dois agentes trabalham neste repositório **ao mesmo tempo**, cada um na sua
worktree e branch. Respeite a divisão abaixo: ela existe para evitar conflitos
de merge e alterações cruzadas.

## Projeto em uma frase

Site estático multipágina (HTML + JS puro, sem build) publicado no GitHub
Pages. Autenticação e dados vêm do Supabase (projeto `slrbjnqgzvryrganuzzr`),
sempre pelo schema `api` (views `vw_*` para leitura, RPCs para escrita).

## Quem cuida de quê

| Área | Dono | Branch | Worktree |
|---|---|---|---|
| Lógica, dados, API, banco, autenticação, segurança | **Claude** | `backend/claude` | `../central_comercial_worktrees/claude-backend` |
| Interface, CSS, layout, navegação, usabilidade, responsividade | **Codex** | `ui/codex` | `../central_comercial_worktrees/codex-ui` |

### Claude (técnico)

- `database/**` (migrations, SQL, RLS, grants, storage, edge functions)
- `assets/js/api.js` (toda a camada de dados: cliente Supabase, views, RPCs, Storage)
- `assets/js/supabase-config.js`, `assets/js/auth-guard.js`, `assets/js/store.js`, `assets/js/app.js`
- Lógica de login em `login.html` (o bloco `<script>`)
- Em `assets/js/ui.js`: apenas a linha `const { ... } = window.Api;` e o bloco
  "Camada de dados" no `return` final, que reexpõe o `Api` como `UI.*Supabase*`
- Em `assets/js/pages/*.js`: somente as chamadas de dados (`UI.createSupabase*`,
  `UI.updateSupabase*`, `UI.hydrateSupabaseSnapshot`, `UI.uploadPrivateFile`)
  e os payloads enviados a elas
- `sw.js` (estratégia de cache), `scripts/**`, `.github/**`

### Codex (interface)

- `assets/css/**`, `assets/images/**`, `manifest.webmanifest`
- `index.html`, `pages/*.html` e o HTML/CSS de `login.html` (mantenha a ordem dos
  `<script>`: `supabase-config` → `auth-guard` → `data` → `store` → `api` → `ui`
  → página → `app`)
- `assets/js/ui.js` inteiro (shell, navegação, menus, drawer, busca, toasts,
  diálogos, skeleton, badges, mapas, animações, formatação visual), exceto o
  trecho de reexportação do `Api` listado na área do Claude
- Em `assets/js/pages/*.js`: renderização (templates HTML), eventos de tela,
  filtros, ordenação, paginação, validação visual de formulários, estados
  vazios/carregando/erro
- `assets/js/pdf-report.js` (layout dos PDFs)

## Contrato entre as camadas

1. As páginas acessam dados **apenas** pelas funções `UI.*Supabase*`,
   `UI.hydrateSupabaseSnapshot` e `UI.uploadPrivateFile`, e leem o estado
   com `Store.getState()`.
2. O Codex **não** renomeia, remove ou muda a assinatura/payload dessas
   funções, e não chama `supabase`, `.rpc()`, `.from()` ou `storage` direto.
3. O Claude **não** altera markup, classes CSS, textos de tela ou layout.
   Se uma mudança técnica exigir alteração visual, registra o pedido em
   `COORDENACAO.md`.
4. O formato dos objetos no `Store` (`clients`, `trips`, `visits`,
   `expenses`, `events`, `users`) é o contrato. Mudanças nele são anunciadas
   em `COORDENACAO.md` antes do merge.
5. Precisa de algo fora da sua área? Escreva em `COORDENACAO.md` em vez de
   editar o arquivo do outro agente.

## Fluxo de trabalho

- Trabalhe somente na sua branch e na sua worktree. Nunca faça commit direto
  no `main` nem `push --force`.
- Antes de começar uma tarefa: `git merge main` para receber o que já foi
  integrado.
- Commits pequenos, no padrão já usado no repositório (Conventional Commits em
  português): `feat(ui): ...`, `fix(auth): ...`, `chore(...)`.
- Quem integra no `main` é o usuário (ou o agente, quando o usuário pedir).
- Servidor local: Claude usa `node scripts/servidor-local.js 8081`,
  Codex usa `node scripts/servidor-local.js 8082`.

## Regras fixas

- Nunca coloque a chave `service_role` ou senhas no frontend ou em commits.
  `supabase-config.js` contém apenas a chave anon/publishable.
- O banco Supabase é **um só** para as duas worktrees. Somente o Claude aplica
  migrations, e sempre com um arquivo novo em `database/migrations/`.
- Não versionar: `app_old.js`, `ids.txt`, arquivos de `scratch/` novos.
