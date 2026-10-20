-- ============================================================================
-- VALIDACAO FINAL SOMENTE-LEITURA - INTEGRACAO PROPOSTAS MHS
-- Execute depois de 20260927_0011_propostas_mhs_templates_completos.sql.
-- ============================================================================

select table_schema, table_name
from information_schema.tables
where table_schema = 'propostas_mhs'
  and table_name in ('propostas', 'propostas_grupos', 'propostas_itens', 'propostas_revisoes', 'templates', 'blocos_inteligentes', 'historico_cpmv_produtos')
order by table_name;

select table_name
from information_schema.views
where table_schema = 'api'
  and table_name in (
    'vw_propostas_mhs', 'vw_clientes_propostas_mhs', 'vw_catalogo_propostas_mhs',
    'vw_templates_propostas_mhs', 'vw_historico_cpmv_mhs', 'vw_blocos_inteligentes_mhs'
  )
order by table_name;

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in (
    'criar_proposta_mhs', 'salvar_proposta_completa_mhs', 'detalhar_proposta_mhs',
    'criar_revisao_proposta_mhs', 'salvar_template_proposta_mhs_v2',
    'salvar_bloco_inteligente_mhs', 'registrar_cpmv_mhs'
  )
order by routine_name;

select id, public, file_size_limit
from storage.buckets
where id = 'propostas-mhs';

select c.relname as tabela, c.relrowsecurity as rls_ativo
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'propostas_mhs' and c.relname in ('propostas', 'propostas_grupos', 'propostas_revisoes', 'templates', 'blocos_inteligentes')
order by c.relname;

-- Consulta as permissoes do papel anon sem assumir esse papel. Assumi-lo aqui
-- impediria a propria resolucao do schema interno, que e justamente bloqueado.
select
  has_schema_privilege('anon', 'propostas_mhs', 'USAGE') as anon_tem_schema_interno,
  has_table_privilege('anon', 'propostas_mhs.propostas', 'SELECT') as anon_le_tabela_interna,
  has_schema_privilege('anon', 'api', 'USAGE') as anon_tem_api;
