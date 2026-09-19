-- ============================================================================
-- ORIGEM TEMPORÁRIA DA MIGRAÇÃO DE CARCINICULTURA
--
-- Esta tabela recebe o CSV completo exportado do mapa antigo. Todas as colunas
-- são texto de propósito: a limpeza e a conversão ocorrem apenas no arquivo 02.
-- Ela não é usada pelo mapa nem pelo CRM depois da migração.
-- ============================================================================

begin;

create table if not exists mapa.origem_carcinicultura_csv (
    linha_origem                    bigint generated always as identity primary key,
    planilha                        text,
    seq                             text,
    cnpj                            text,
    razao_social                    text,
    nome_fantasia                   text,
    situacao_cadastral              text,
    uf                              text,
    municipio                       text,
    abertura                        text,
    cnae                            text,
    logradouro                      text,
    motivo_situacao                 text,
    porte                           text,
    bairro                          text,
    cep                             text,
    email                           text,
    telefone                        text,
    telefone_1                      text,
    capital_social                  text,
    optante_simples                 text,
    qtd_socios                      text,
    optante_mei                     text,
    endereco_busca                  text,
    latitude                        text,
    longitude                       text,
    geocode_status                  text,
    cliente_id                      text,
    cnpj_normalizado                text,
    origem_registro                 text,
    contato_nome                    text,
    contato_cargo                   text,
    whatsapp                        text,
    canal_preferido                 text,
    observacoes_comerciais          text,
    latitude_confirmada             text,
    longitude_confirmada            text,
    localizacao_status              text,
    localizacao_fonte               text,
    localizacao_precisao_m          text,
    localizacao_observacao          text,
    localizacao_confirmada_em       text,
    localizacao_confirmada_por      text,
    criado_em                       text,
    atualizado_em                   text,
    criado_por                      text,
    atualizado_por                  text,
    revisao                         text,
    google_place_id                 text,
    google_latitude                 text,
    google_longitude                text,
    google_location_type            text,
    google_formatted_address        text,
    google_geocode_status           text,
    google_geocoded_at              text,
    google_geocode_expires_at       text,
    google_geocode_attempts         text,
    google_geocode_error            text,
    google_geocode_source_address   text,
    google_geocode_validated        text,
    google_geocode_validation_note  text
);

comment on table mapa.origem_carcinicultura_csv is
'Fonte privada e temporária do CSV completo. Usada somente para a primeira migração de carcinicultura.';

revoke all on mapa.origem_carcinicultura_csv from public, anon, authenticated;
grant all privileges on mapa.origem_carcinicultura_csv to service_role;
alter table mapa.origem_carcinicultura_csv enable row level security;

commit;
