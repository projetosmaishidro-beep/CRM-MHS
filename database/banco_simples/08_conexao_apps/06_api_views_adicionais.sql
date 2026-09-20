begin;

-- ==============================================================================
-- 1. TABELA DE EVENTOS E VIEW
-- ==============================================================================
create table if not exists crm.eventos (
    evento_id                   uuid primary key default gen_random_uuid(),
    nome                        text not null,
    local                       text,
    data_inicio                 date,
    data_fim                    date,
    status                      text not null default 'PLANEJADO',
    tipo_participacao           text not null default 'PARTICIPANTE',
    notas_estrategicas          text,
    participantes               jsonb default '[]'::jsonb,
    anexos                      jsonb default '[]'::jsonb,
    links                       jsonb default '[]'::jsonb,
    contatos                    jsonb default '[]'::jsonb,
    criado_por                  uuid references auth.users(id) on delete set null,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint eventos_status_check check (status in ('PLANEJADO', 'EM_ANDAMENTO', 'REALIZADO', 'CANCELADO')),
    constraint eventos_tipo_check check (tipo_participacao in ('PARTICIPANTE', 'EXPOSITOR', 'PATROCINADOR', 'VISITANTE'))
);

drop view if exists api.vw_eventos cascade;
create or replace view api.vw_eventos
with (security_invoker = true)
as
select 
    evento_id,
    nome,
    local,
    data_inicio,
    data_fim,
    status,
    tipo_participacao,
    notas_estrategicas,
    participantes,
    anexos,
    links,
    contatos,
    criado_em,
    criado_por
from crm.eventos;

-- ==============================================================================
-- 2. DESPESAS DE EVENTOS E VIEW
-- ==============================================================================
alter table crm.despesas alter column viagem_id drop not null;
alter table crm.despesas add column if not exists evento_id uuid references crm.eventos(evento_id) on delete cascade;
alter table crm.despesas add column if not exists criado_por uuid references auth.users(id) on delete set null;

drop view if exists api.vw_despesas_eventos cascade;
create or replace view api.vw_despesas_eventos
with (security_invoker = true)
as
select 
    d.despesa_id,
    d.evento_id,
    d.criado_por,
    d.categoria,
    null as centro_custo, 
    d.valor,
    null as estabelecimento,
    d.observacao as descricao,
    d.ocorrido_em as data_despesa,
    d.criado_em
from crm.despesas d
where d.evento_id is not null;

-- ==============================================================================
-- 3. ROTAS E VISITAS (MAPA)
-- ==============================================================================
drop view if exists api.vw_rotas_visitas cascade;
create or replace view api.vw_rotas_visitas
with (security_invoker = true)
as
select 
    v.viagem_id as rota_id,
    v.titulo,
    v.inicio_em as data_planejada,
    v.status,
    (select count(*) from crm.visitas where viagem_id = v.viagem_id) as total_paradas,
    (select count(*) from crm.visitas where viagem_id = v.viagem_id and status = 'REALIZADA') as paradas_visitadas,
    (select count(*) from crm.visitas where viagem_id = v.viagem_id and status = 'PLANEJADA') as paradas_pendentes,
    v.criado_em
from crm.viagens v;

-- ==============================================================================
-- 4. ATIVIDADE RECENTE DE CLIENTES (MAPA)
-- ==============================================================================
drop view if exists api.vw_atividade_clientes cascade;
create or replace view api.vw_atividade_clientes
with (security_invoker = true)
as
select 
    v.visita_id as evento_id,
    coalesce(v.realizada_em, v.agendada_para, v.criado_em) as ocorrido_em,
    'VISITA ' || v.status as tipo_evento,
    v.empresa_id as cliente_id,
    e.razao_social as cliente,
    e.municipio,
    e.uf,
    eq.nome as operador
from crm.visitas v
join cadastro.empresas e on v.empresa_id = e.empresa_id
left join mapa.pontos p on e.empresa_id = p.empresa_id
left join cadastro.equipe eq on v.criado_por = eq.usuario_id;

commit;

