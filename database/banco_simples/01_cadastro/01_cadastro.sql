-- ============================================================================
-- SCHEMA: cadastro
-- Ficha única de cada empresa/unidade que pode aparecer no mapa ou no CRM.
-- Execute este arquivo primeiro.
-- ============================================================================

begin;

create extension if not exists pgcrypto with schema extensions;

create schema if not exists cadastro;

comment on schema cadastro is
'Cadastro compartilhado pelo mapa e pelo CRM. Uma linha representa uma empresa/unidade visitável.';

create table if not exists cadastro.empresas (
    empresa_id                  uuid primary key default gen_random_uuid(),
    cnpj                        text unique,
    razao_social                text,
    nome_fantasia               text,
    categoria                   text not null default 'PENDENTE_CLASSIFICACAO',
    situacao_cadastral          text,
    logradouro                  text,
    bairro                      text,
    municipio                   text,
    uf                           text,
    cep                          text,
    contato_nome                text,
    contato_cargo               text,
    telefone                    text,
    whatsapp                    text,
    email                       text,
    cliente_id_legado           uuid unique,
    origem                      text not null default 'IMPORTACAO_MAPA',
    criado_em                   timestamptz not null default now(),
    atualizado_em               timestamptz not null default now(),
    constraint empresas_cnpj_check
        check (cnpj is null or cnpj ~ '^\d{14}$'),
    constraint empresas_categoria_check
        check (categoria in (
            'CARCINICULTOR',
            'IRRIGACAO',
            'CONSTRUCAO_CIVIL',
            'MINERACAO',
            'CONDOMINIAL',
            'OUTRO',
            'PENDENTE_CLASSIFICACAO'
        )),
    constraint empresas_uf_check
        check (uf is null or uf ~ '^[A-Z]{2}$'),
    constraint empresas_cep_check
        check (cep is null or cep ~ '^\d{8}$')
);

comment on table cadastro.empresas is
'Cadastro mestre. O mapa e o CRM usam empresa_id e não duplicam estes dados.';
comment on column cadastro.empresas.empresa_id is
'Identificador interno permanente da empresa.';
comment on column cadastro.empresas.cnpj is
'CNPJ sem pontuação. Pode ficar vazio no cadastro de campo ainda não validado.';
comment on column cadastro.empresas.categoria is
'Categoria comercial simples definida pela equipe ou por regra de importação.';
comment on column cadastro.empresas.situacao_cadastral is
'Situação legal de origem, como ATIVA ou INAPTA. Não define sozinha lead ou cliente.';
comment on column cadastro.empresas.cliente_id_legado is
'UUID que já existia no banco antigo do mapa, preservado para rastreabilidade.';
comment on column cadastro.empresas.origem is
'Como o cadastro entrou no ecossistema: IMPORTACAO_MAPA ou CADASTRO_CAMPO.';

create index if not exists empresas_categoria_idx
    on cadastro.empresas (categoria);

create index if not exists empresas_municipio_uf_idx
    on cadastro.empresas (municipio, uf);

revoke all on schema cadastro from public;
revoke all on all tables in schema cadastro from public, anon, authenticated;
grant usage on schema cadastro to authenticated, service_role;
grant all privileges on all tables in schema cadastro to service_role;

alter table cadastro.empresas enable row level security;

commit;
