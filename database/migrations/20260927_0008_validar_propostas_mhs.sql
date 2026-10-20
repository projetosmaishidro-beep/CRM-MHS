-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - PROPOSTAS MHS
-- Execute depois das migracoes 0004, 0005, 0006 e 0007.
-- Este arquivo nao cria, altera nem remove dados.
-- ============================================================================

-- 1. Schema e tabelas essenciais
select table_schema, table_name
from information_schema.tables
where table_schema = 'propostas_mhs'
  and table_name in (
    'clientes', 'locais_obra', 'catalogo_itens', 'catalogo_composicoes',
    'catalogo_composicoes_versoes', 'catalogo_composicao_componentes',
    'historico_cpmv_produtos', 'historico_precos_venda',
    'blocos_inteligentes', 'blocos_inteligentes_versoes',
    'templates', 'templates_versoes', 'propostas', 'propostas_itens',
    'propostas_itens_composicao', 'propostas_condicoes',
    'propostas_pagamentos', 'propostas_escopo', 'memorias_calculo',
    'memorias_calculo_linhas', 'propostas_revisoes', 'arquivos_proposta',
    'arquivos_template', 'historico_acoes'
  )
order by table_name;

-- 2. RLS deve estar ativo em todas as tabelas do modulo.
select c.relname as tabela, c.relrowsecurity as rls_ativo
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'propostas_mhs' and c.relkind = 'r'
order by c.relname;

-- 3. Views e funcoes publicadas pela API autenticada.
select table_name as view_api
from information_schema.views
where table_schema = 'api'
  and table_name in (
    'vw_propostas_mhs', 'vw_clientes_propostas_mhs',
    'vw_catalogo_propostas_mhs', 'vw_templates_propostas_mhs',
    'vw_historico_cpmv_mhs'
  )
order by table_name;

select routine_name, data_type as retorno
from information_schema.routines
where routine_schema = 'api'
  and routine_name in (
    'detalhar_proposta_mhs', 'criar_proposta_mhs',
    'atualizar_cabecalho_proposta_mhs', 'salvar_conteudo_proposta_mhs',
    'criar_revisao_proposta_mhs', 'detalhar_revisao_proposta_mhs',
    'salvar_item_catalogo_mhs', 'criar_versao_composicao_mhs',
    'registrar_cpmv_mhs', 'registrar_preco_venda_mhs',
    'salvar_bloco_inteligente_mhs', 'salvar_template_proposta_mhs',
    'obter_template_proposta_mhs', 'registrar_arquivo_proposta_mhs',
    'registrar_arquivo_template_mhs'
  )
order by routine_name;

-- 4. Bucket, limite e politicas de arquivos.
select id, public, file_size_limit, allowed_mime_types
from storage.buckets
where id = 'propostas-mhs';

select policyname, cmd, roles
from pg_policies
where schemaname = 'storage'
  and tablename = 'objects'
  and policyname like 'propostas_mhs_%'
order by policyname;

-- 5. Checagem de acesso: anon nao pode usar schema ou tabelas internas.
begin;
set local role anon;
select
  has_schema_privilege('anon', 'propostas_mhs', 'USAGE') as anon_tem_schema_propostas,
  has_table_privilege('anon', 'propostas_mhs.propostas', 'SELECT') as anon_le_propostas,
  has_schema_privilege('anon', 'api', 'USAGE') as anon_tem_api;
rollback;

-- 6. Integridade da chave universal e historico imutavel.
select conrelid::regclass as tabela, conname as restricao, pg_get_constraintdef(oid) as definicao
from pg_constraint
where conrelid in (
  'propostas_mhs.propostas'::regclass,
  'propostas_mhs.propostas_revisoes'::regclass,
  'propostas_mhs.arquivos_proposta'::regclass
)
order by conrelid::regclass::text, conname;

select tgrelid::regclass as tabela, tgname as gatilho
from pg_trigger
where not tgisinternal
  and tgrelid in (
    'propostas_mhs.propostas_revisoes'::regclass,
    'propostas_mhs.templates_versoes'::regclass,
    'propostas_mhs.catalogo_composicoes_versoes'::regclass
  )
order by tgrelid::regclass::text, tgname;

