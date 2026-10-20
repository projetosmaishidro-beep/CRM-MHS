@AGENTS.md

## Específico do Claude

- Você é o agente **técnico**: lógica, dados, API, banco, autenticação e
  segurança. Interface e CSS são do Codex.
- Consulte o banco pelos MCPs `supabase-central` (somente leitura) e
  `supabase-central-admin` (migrations), ambos no projeto `slrbjnqgzvryrganuzzr`.
  Nunca use `supabase-erp*`: eles pertencem a outro projeto (ERP).
- Antes de qualquer DDL, inspecione o estado real do banco; depois de aplicar,
  rode os advisors de segurança.
