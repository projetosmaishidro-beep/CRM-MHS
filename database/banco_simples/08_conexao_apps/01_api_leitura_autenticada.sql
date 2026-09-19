-- ============================================================================
-- API DE LEITURA PARA CRM E MAPA
--
-- Esta camada expõe somente duas views para aplicativos autenticados:
--   api.vw_carteira_crm  -> CRM (clientes e leads)
--   api.vw_mapa_clientes -> mapa (dados e coordenadas)
--
-- As tabelas cadastro, mapa e crm continuam internas e não devem ser
-- adicionadas aos "Exposed schemas" do Supabase.
-- ============================================================================

begin;

create schema if not exists api;

comment on schema api is
'Superfície mínima da Data API para os aplicativos. Não armazena dados; somente views autorizadas.';

-- Nenhuma leitura é concedida para visitantes não autenticados.
revoke all on schema api from public, anon;
revoke all on all tables in schema api from public, anon;
grant usage on schema api to authenticated, service_role;

-- As views abaixo usam security_invoker. Portanto, estes grants e as políticas
-- RLS das tabelas de origem também são obrigatórios para a leitura funcionar.
grant usage on schema cadastro, mapa, crm to authenticated;

grant select on table cadastro.empresas to authenticated;
grant select on table mapa.pontos to authenticated;
grant select on table crm.relacionamentos to authenticated;

drop policy if exists equipe_le_dados_comerciais on cadastro.empresas;
create policy equipe_le_dados_comerciais
on cadastro.empresas
for select
to authenticated
using (true);

drop policy if exists equipe_le_pontos_do_mapa on mapa.pontos;
create policy equipe_le_pontos_do_mapa
on mapa.pontos
for select
to authenticated
using (true);

drop policy if exists equipe_le_carteira on crm.relacionamentos;
create policy equipe_le_carteira
on crm.relacionamentos
for select
to authenticated
using (true);

-- Uma única leitura para as listas e filtros do CRM.
-- Não inclui arquivos, histórico de auditoria, importações ou anexos privados.
create or replace view api.vw_carteira_crm
with (security_invoker = true)
as
select
    e.empresa_id,
    r.relacionamento_id,
    r.tipo as tipo_relacionamento,
    r.status as status_relacionamento,
    coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Empresa sem nome') as empresa,
    e.razao_social,
    e.nome_fantasia,
    e.cnpj,
    e.categoria,
    e.situacao_cadastral,
    e.logradouro,
    e.bairro,
    e.municipio,
    e.uf,
    e.cep,
    e.contato_nome,
    e.contato_cargo,
    e.telefone,
    e.whatsapp,
    e.email,
    e.origem as origem_registro,
    p.ponto_id,
    p.latitude,
    p.longitude,
    p.status_confirmacao,
    p.fonte_localizacao,
    p.precisao_m,
    p.confirmado_em,
    p.observacao as observacao_localizacao,
    r.cliente_desde,
    r.criado_em as relacionamento_criado_em,
    r.atualizado_em as relacionamento_atualizado_em
from crm.relacionamentos r
join cadastro.empresas e on e.empresa_id = r.empresa_id
left join mapa.pontos p on p.empresa_id = e.empresa_id
where r.status = 'ATIVO';

comment on view api.vw_carteira_crm is
'Lista autenticada da carteira comercial: clientes e leads, com apenas os campos necessários ao CRM.';

-- Formato compatível com o leitor do aplicativo de mapa. O campo cliente_id
-- é o empresa_id do novo banco: o identificador não muda entre CRM e mapa.
create or replace view api.vw_mapa_clientes
with (security_invoker = true)
as
select
    empresa_id as cliente_id,
    empresa_id,
    relacionamento_id,
    tipo_relacionamento as tipo_crm,
    empresa as nome_exibicao,
    razao_social,
    nome_fantasia,
    cnpj,
    categoria,
    situacao_cadastral,
    uf,
    municipio,
    bairro,
    logradouro,
    cep,
    contato_nome,
    contato_cargo,
    telefone,
    telefone as telefone_1,
    whatsapp,
    email,
    latitude,
    longitude,
    case when status_confirmacao = 'CONFIRMADO_CAMPO' then latitude end as latitude_confirmada,
    case when status_confirmacao = 'CONFIRMADO_CAMPO' then longitude end as longitude_confirmada,
    case
        when status_confirmacao = 'CONFIRMADO_CAMPO' then 'CONFIRMADA_CAMPO'
        when status_confirmacao = 'APROXIMADO_MUNICIPIO' then 'APROX_SEDE_MUNICIPIO'
        else status_confirmacao
    end as localizacao_status,
    fonte_localizacao as localizacao_fonte,
    precisao_m as precisao_efetiva,
    observacao_localizacao as localizacao_observacao,
    origem_registro,
    case
        when origem_registro = 'CADASTRO_CAMPO' then 'NOVO'
        else 'BASE_ORIGINAL'
    end as classificacao_registro,
    1 as revisao,
    relacionamento_atualizado_em as reposicionado_em,
    status_confirmacao,
    confirmado_em,
    cliente_desde
from api.vw_carteira_crm;

comment on view api.vw_mapa_clientes is
'Leitura autenticada do mapa, com coordenadas e precisão. Não oferece escrita nem acesso a evidências.';

revoke all on api.vw_carteira_crm, api.vw_mapa_clientes from public, anon;
grant select on api.vw_carteira_crm, api.vw_mapa_clientes to authenticated, service_role;

commit;
