-- ============================================================================
-- SCHEMA: crm
-- Relação comercial e operação. Não duplica dados de empresa ou de mapa.
-- Execute após 01_cadastro/01_cadastro.sql e 02_mapa/02_mapa.sql.
-- ============================================================================

begin;

create schema if not exists crm;

comment on schema crm is
'Dados comerciais e operacionais da Central Comercial.';

create table if not exists crm.relacionamentos (
    relacionamento_id           uuid primary key default gen_random_uuid(),
    empresa_id                  uuid not null unique references cadastro.empresas(empresa_id) on delete restrict,
    tipo                        text not null default 'LEAD',
    status                      text not null default 'ATIVO',
    responsavel_por             uuid references auth.users(id) on delete set null,
    origem                      text not null default 'MAPA',
    cliente_desde               timestamptz,
    observacao                  text,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint relacionamentos_tipo_check
        check (tipo in ('LEAD', 'CLIENTE')),
    constraint relacionamentos_status_check
        check (status in ('ATIVO', 'ARQUIVADO'))
);

comment on table crm.relacionamentos is
'Situação comercial da empresa. LEAD ou CLIENTE é sincronizado a partir da confirmação no mapa.';
comment on column crm.relacionamentos.cliente_desde is
'Primeira data em que um ponto confirmado promoveu a empresa a cliente.';

create index if not exists relacionamentos_tipo_status_idx
    on crm.relacionamentos (tipo, status);

create table if not exists crm.viagens (
    viagem_id                   uuid primary key default gen_random_uuid(),
    titulo                      text not null,
    status                      text not null default 'PLANEJADA',
    inicio_em                   timestamptz,
    fim_em                      timestamptz,
    km_inicial                  numeric(12,1),
    km_final                    numeric(12,1),
    observacao                  text,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint viagens_status_check
        check (status in ('PLANEJADA', 'EM_ANDAMENTO', 'CONCLUIDA', 'CANCELADA')),
    constraint viagens_km_check
        check (
            (km_inicial is null and km_final is null)
            or km_final is null
            or km_inicial is null
            or km_final >= km_inicial
        )
);

create table if not exists crm.visitas (
    visita_id                   uuid primary key default gen_random_uuid(),
    empresa_id                  uuid not null references cadastro.empresas(empresa_id) on delete restrict,
    viagem_id                   uuid references crm.viagens(viagem_id) on delete set null,
    status                      text not null default 'PLANEJADA',
    agendada_para               timestamptz,
    realizada_em                timestamptz,
    resultado                   text,
    observacao                  text,
    criado_por                  uuid references auth.users(id) on delete set null,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint visitas_status_check
        check (status in ('PLANEJADA', 'REALIZADA', 'CANCELADA'))
);

create index if not exists visitas_empresa_data_idx
    on crm.visitas (empresa_id, realizada_em desc);

create table if not exists crm.necessidades (
    necessidade_id              uuid primary key default gen_random_uuid(),
    empresa_id                  uuid not null references cadastro.empresas(empresa_id) on delete restrict,
    visita_id                   uuid references crm.visitas(visita_id) on delete set null,
    categoria                   text not null,
    descricao                   text not null,
    prioridade                  text not null default 'MEDIA',
    status                      text not null default 'ABERTA',
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint necessidades_prioridade_check
        check (prioridade in ('BAIXA', 'MEDIA', 'ALTA')),
    constraint necessidades_status_check
        check (status in ('ABERTA', 'EM_ANALISE', 'ATENDIDA', 'CANCELADA'))
);

create table if not exists crm.despesas (
    despesa_id                  uuid primary key default gen_random_uuid(),
    viagem_id                   uuid not null references crm.viagens(viagem_id) on delete cascade,
    categoria                   text not null,
    valor                       numeric(14,2) not null check (valor >= 0),
    ocorrido_em                 date not null default current_date,
    observacao                  text,
    criado_em                   timestamptz not null default now()
);

create table if not exists crm.anexos (
    anexo_id                    uuid primary key default gen_random_uuid(),
    empresa_id                  uuid references cadastro.empresas(empresa_id) on delete cascade,
    visita_id                   uuid references crm.visitas(visita_id) on delete cascade,
    viagem_id                   uuid references crm.viagens(viagem_id) on delete cascade,
    despesa_id                  uuid references crm.despesas(despesa_id) on delete cascade,
    bucket                      text not null,
    caminho                     text not null unique,
    nome_arquivo                text not null,
    tipo_arquivo                text,
    tamanho_bytes               bigint,
    criado_em                   timestamptz not null default now(),
    constraint anexos_destino_check
        check (
            empresa_id is not null
            or visita_id is not null
            or viagem_id is not null
            or despesa_id is not null
        ),
    constraint anexos_bucket_check
        check (bucket in ('crm-anexos', 'financeiro-comprovantes'))
);

comment on table crm.anexos is
'Índice dos arquivos privados. O arquivo fica no Storage; esta tabela informa a que registro ele pertence.';

create or replace view crm.vw_leads
with (security_invoker = true)
as
select
    r.relacionamento_id,
    e.empresa_id,
    coalesce(e.nome_fantasia, e.razao_social) as empresa,
    e.categoria,
    e.municipio,
    e.uf,
    r.status,
    r.responsavel_por,
    r.criado_em
from crm.relacionamentos r
join cadastro.empresas e on e.empresa_id = r.empresa_id
where r.tipo = 'LEAD';

create or replace view crm.vw_clientes
with (security_invoker = true)
as
select
    r.relacionamento_id,
    e.empresa_id,
    coalesce(e.nome_fantasia, e.razao_social) as empresa,
    e.categoria,
    e.municipio,
    e.uf,
    r.status,
    r.responsavel_por,
    r.cliente_desde
from crm.relacionamentos r
join cadastro.empresas e on e.empresa_id = r.empresa_id
where r.tipo = 'CLIENTE';

revoke all on schema crm from public;
revoke all on all tables in schema crm from public, anon, authenticated;
grant usage on schema crm to authenticated, service_role;
grant all privileges on all tables in schema crm to service_role;

alter table crm.relacionamentos enable row level security;
alter table crm.viagens enable row level security;
alter table crm.visitas enable row level security;
alter table crm.necessidades enable row level security;
alter table crm.despesas enable row level security;
alter table crm.anexos enable row level security;

commit;
