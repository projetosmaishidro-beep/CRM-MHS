-- ============================================================================
-- VALIDAÇÃO DA MIGRAÇÃO DE CARCINICULTURA
-- Todas as consultas são somente leitura.
-- ============================================================================

-- Total da origem e total já carregado com categoria carcinicultura.
select
    (select count(*)
       from mapa.origem_carcinicultura_csv
      where substring(cnae from '^[[:space:]]*([0-9]{5,7})') in ('321302', '322102')) as origem_carcinicultura,
    (select count(*)
       from cadastro.empresas
      where categoria = 'CARCINICULTOR') as empresas_carcinicultoras,
    (select count(*)
       from crm.vw_clientes c
       join cadastro.empresas e on e.empresa_id = c.empresa_id
      where e.categoria = 'CARCINICULTOR') as clientes_confirmados,
    (select count(*)
       from crm.vw_leads l
       join cadastro.empresas e on e.empresa_id = l.empresa_id
      where e.categoria = 'CARCINICULTOR') as leads;

-- Não pode existir divergência entre ponto e classificação CRM.
select
    empresa.empresa_id,
    coalesce(empresa.nome_fantasia, empresa.razao_social) as empresa,
    ponto.status_confirmacao,
    relacionamento.tipo as tipo_crm
from cadastro.empresas empresa
join mapa.pontos ponto on ponto.empresa_id = empresa.empresa_id
left join crm.relacionamentos relacionamento on relacionamento.empresa_id = empresa.empresa_id
where empresa.categoria = 'CARCINICULTOR'
  and (
      (ponto.status_confirmacao = 'CONFIRMADO_CAMPO' and coalesce(relacionamento.tipo, '') <> 'CLIENTE')
      or
      (ponto.status_confirmacao <> 'CONFIRMADO_CAMPO' and coalesce(relacionamento.tipo, '') <> 'LEAD')
  );

-- Pontos confirmados trazidos do banco antigo devem conservar a identificação
-- do operador legado até o usuário equivalente existir no novo Supabase.
select
    empresa.empresa_id,
    coalesce(empresa.nome_fantasia, empresa.razao_social) as empresa,
    ponto.confirmado_em,
    ponto.confirmado_por,
    ponto.confirmado_por_legado
from cadastro.empresas empresa
join mapa.pontos ponto on ponto.empresa_id = empresa.empresa_id
where empresa.categoria = 'CARCINICULTOR'
  and ponto.status_confirmacao = 'CONFIRMADO_CAMPO'
  and ponto.confirmado_por is null
  and nullif(trim(ponto.confirmado_por_legado), '') is null;

-- Histórico esperado da primeira carga.
select
    tabela_origem,
    acao,
    count(*) as eventos
from cadastro.historico
where tabela_origem in ('empresas', 'pontos', 'relacionamentos')
group by tabela_origem, acao
order by tabela_origem, acao;
