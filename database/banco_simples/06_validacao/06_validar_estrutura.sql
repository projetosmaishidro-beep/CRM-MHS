-- ============================================================================
-- VALIDAÇÃO
-- Consultas de leitura para conferir a estrutura e, posteriormente, a carga.
-- ============================================================================

-- As tabelas principais e o histórico de auditoria devem existir.
select table_schema, table_name
from information_schema.tables
where (table_schema, table_name) in (
    ('cadastro', 'empresas'),
    ('cadastro', 'historico'),
    ('mapa', 'pontos'),
    ('mapa', 'importacoes'),
    ('mapa', 'importacao_empresas'),
    ('mapa', 'evidencias_ponto'),
    ('crm', 'relacionamentos'),
    ('crm', 'viagens'),
    ('crm', 'visitas'),
    ('crm', 'necessidades'),
    ('crm', 'despesas'),
    ('crm', 'anexos')
)
order by table_schema, table_name;

-- Depois da migração, estes totais devem demonstrar que cada empresa com ponto
-- possui exatamente um relacionamento CRM e que o tipo respeita a regra do mapa.
select
    (select count(*) from cadastro.empresas) as empresas,
    (select count(*) from mapa.pontos) as pontos,
    (select count(*) from crm.relacionamentos) as relacionamentos,
    (select count(*) from crm.vw_clientes) as clientes,
    (select count(*) from crm.vw_leads) as leads;

select
    p.empresa_id,
    p.status_confirmacao,
    r.tipo as tipo_crm
from mapa.pontos p
left join crm.relacionamentos r on r.empresa_id = p.empresa_id
where (
    p.status_confirmacao = 'CONFIRMADO_CAMPO'
    and coalesce(r.tipo, '') <> 'CLIENTE'
) or (
    p.status_confirmacao <> 'CONFIRMADO_CAMPO'
    and coalesce(r.tipo, '') <> 'LEAD'
);

-- O histórico permite auditar qualquer empresa, ponto ou registro operacional.
-- Após a carga, deve haver ao menos uma criação para cada registro migrado.
select
    schema_origem,
    tabela_origem,
    acao,
    count(*) as total_eventos,
    max(ocorrido_em) as ultimo_evento_em
from cadastro.historico
group by schema_origem, tabela_origem, acao
order by schema_origem, tabela_origem, acao;
