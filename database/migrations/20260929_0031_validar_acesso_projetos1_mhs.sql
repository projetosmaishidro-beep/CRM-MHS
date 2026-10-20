-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - ACESSO OPERACIONAL MHS
-- Execute depois de 20260929_0030_estabilizar_historico_rascunhos_mhs.sql.
-- ============================================================================

select
  lower(u.email) as email,
  u.id as usuario_id,
  e.membro_id,
  e.ativo,
  e.papel,
  has_schema_privilege('authenticated', 'api', 'USAGE') as api_disponivel,
  has_table_privilege('authenticated', 'api.vw_carteira_crm', 'SELECT') as carteira_disponivel,
  has_function_privilege(
    'authenticated',
    'api.listar_galeria_pdfs_propostas_mhs(text, boolean, text, integer, timestamptz, uuid, text, integer)',
    'EXECUTE'
  ) as galeria_disponivel
from auth.users u
left join cadastro.equipe e on e.usuario_id = u.id
where lower(u.email) = 'projetos1@maisintegradora.com.br';
