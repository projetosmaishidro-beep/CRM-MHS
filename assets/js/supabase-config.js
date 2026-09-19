/*
 * Configuração centralizada do Supabase.
 *
 * Este arquivo é carregado por TODAS as páginas do CRM e do mapa.
 * A URL e a chave anon são públicas por definição do Supabase — a segurança
 * vem exclusivamente do RLS e das policies do banco, nunca de esconder a chave.
 *
 * Somente o administrador pode visualizar/alterar esses valores pela interface.
 * Os demais usuários apenas consomem a conexão já configurada.
 *
 * INSTRUÇÕES:
 * 1. Abra o dashboard do seu projeto Supabase.
 * 2. Vá em Settings → API (ou clique em "Connect").
 * 3. Copie a Project URL e cole em SUPABASE_URL.
 * 4. Copie a chave "anon" / "publishable" e cole em SUPABASE_ANON_KEY.
 * 5. Salve o arquivo e faça deploy.
 */
window.SUPABASE_CONFIG = Object.freeze({

  /* URL do projeto Supabase (ex: https://abcdefgh.supabase.co) */
  SUPABASE_URL: "https://slrbjnqgzvryrganuzzr.supabase.co",

  /* Chave pública anon/publishable (NUNCA use service_role aqui) */
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNscmJqbnFnenZyeXJnYW51enpyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4MTA5MjcsImV4cCI6MjEwNTM4NjkyN30.VNfubeJLfusK-13xjS7roUm8AVZ2SQ4kxcf4lD1cCZw",

  /* E-mails com permissão de administrador (podem ver/alterar configurações) */
  ADMIN_EMAILS: [
    "comercial3@maisintegradora.com"
  ]
});
