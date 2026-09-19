-- ============================================================================
-- SCHEMA: mapa
-- Ponto de cada empresa, confirmação de campo, evidências e importações.
-- Execute após 01_cadastro/01_cadastro.sql.
-- ============================================================================

begin;

create schema if not exists mapa;

comment on schema mapa is
'Dados geográficos e de importação do aplicativo de mapa.';

create table if not exists mapa.pontos (
    ponto_id                    uuid primary key default gen_random_uuid(),
    empresa_id                  uuid not null unique references cadastro.empresas(empresa_id) on delete cascade,
    latitude                    numeric(10,7),
    longitude                   numeric(10,7),
    status_confirmacao          text not null default 'PENDENTE',
    fonte_localizacao           text,
    precisao_m                  numeric(10,2),
    confirmado_em               timestamptz,
    confirmado_por              uuid references auth.users(id) on delete set null,
    confirmado_por_legado       text,
    observacao                  text,
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint pontos_status_confirmacao_check
        check (status_confirmacao in (
            'CONFIRMADO_CAMPO',
            'APROXIMADO_MUNICIPIO',
            'PENDENTE',
            'AMBIGUO'
        )),
    constraint pontos_latitude_check
        check (latitude is null or latitude between -34.2 and 5.4),
    constraint pontos_longitude_check
        check (longitude is null or longitude between -74.1 and -32.2),
    constraint pontos_coordenadas_par_check
        check (
            (latitude is null and longitude is null)
            or (latitude is not null and longitude is not null)
        ),
    constraint pontos_confirmado_tem_coordenadas_check
        check (
            status_confirmacao <> 'CONFIRMADO_CAMPO'
            or (latitude is not null and longitude is not null)
        ),
    constraint pontos_confirmado_tem_registro_check
        check (
            status_confirmacao <> 'CONFIRMADO_CAMPO'
            or (
                confirmado_em is not null
                and (
                    confirmado_por is not null
                    or nullif(trim(confirmado_por_legado), '') is not null
                )
            )
        )
);

comment on table mapa.pontos is
'Um ponto atual por empresa. O status deste ponto determina se o CRM a trata como lead ou cliente.';
comment on column mapa.pontos.status_confirmacao is
'CONFIRMADO_CAMPO, com coordenadas, data e operador atual ou legado, promove para cliente; os demais status mantêm a empresa como lead.';
comment on column mapa.pontos.confirmado_por_legado is
'Identificador do operador do banco antigo, preservado até existir o usuário correspondente no novo Supabase.';
comment on column mapa.pontos.fonte_localizacao is
'Origem da coordenada, por exemplo CAMPO, SEDE_MUNICIPIO ou GEOCODIFICACAO.';
comment on column mapa.pontos.precisao_m is
'Raio estimado de precisão da coordenada, em metros.';

create index if not exists pontos_status_confirmacao_idx
    on mapa.pontos (status_confirmacao);

create table if not exists mapa.importacoes (
    importacao_id               uuid primary key default gen_random_uuid(),
    nome                        text not null,
    arquivo_bucket              text not null default 'importacoes-privadas',
    arquivo_caminho             text not null,
    total_linhas                integer,
    checksum                    text,
    importado_em                timestamptz not null default now(),
    observacao                  text
);

comment on table mapa.importacoes is
'Registro de cada arquivo original importado. O arquivo permanece no bucket privado para auditoria.';

create table if not exists mapa.importacao_empresas (
    importacao_id               uuid not null references mapa.importacoes(importacao_id) on delete cascade,
    empresa_id                  uuid not null references cadastro.empresas(empresa_id) on delete cascade,
    linha_origem                integer,
    primary key (importacao_id, empresa_id),
    unique (importacao_id, linha_origem)
);

comment on table mapa.importacao_empresas is
'Liga cada empresa à linha que a originou no arquivo importado.';

create table if not exists mapa.evidencias_ponto (
    evidencia_id                uuid primary key default gen_random_uuid(),
    ponto_id                    uuid not null references mapa.pontos(ponto_id) on delete cascade,
    bucket                      text not null default 'mapa-evidencias',
    caminho                     text not null unique,
    nome_arquivo                text not null,
    tipo_arquivo                text,
    tamanho_bytes               bigint,
    criado_em                   timestamptz not null default now()
);

comment on table mapa.evidencias_ponto is
'Foto, documento ou outro arquivo que comprova a localização de campo.';

revoke all on schema mapa from public;
revoke all on all tables in schema mapa from public, anon, authenticated;
grant usage on schema mapa to authenticated, service_role;
grant all privileges on all tables in schema mapa to service_role;

alter table mapa.pontos enable row level security;
alter table mapa.importacoes enable row level security;
alter table mapa.importacao_empresas enable row level security;
alter table mapa.evidencias_ponto enable row level security;

commit;
