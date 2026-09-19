-- ============================================================================
-- ESCRITA AUTENTICADA DE VIAGENS
--
-- Execute depois de 03_crm.sql, 04_regras e 01_api_leitura_autenticada.sql.
-- A aplicação grava por uma função autenticada no schema api e lê pela view
-- api.vw_viagens. Não há acesso direto das aplicações às tabelas internas.
-- ============================================================================

begin;

alter table crm.viagens
    add column if not exists participantes jsonb not null default '[]'::jsonb;

alter table crm.viagens
    add column if not exists empresas_planejadas jsonb not null default '[]'::jsonb;

comment on column crm.viagens.participantes is
'Snapshot simples dos participantes selecionados no planejamento da viagem.';
comment on column crm.viagens.empresas_planejadas is
'Snapshot simples dos clientes planejados, com id, nome e cidade para o roteiro.';

revoke all on table crm.viagens from public, anon, authenticated;
grant select on table crm.viagens to authenticated, service_role;
grant usage on schema api to authenticated, service_role;

drop policy if exists equipe_le_viagens on crm.viagens;
create policy equipe_le_viagens
on crm.viagens
for select
to authenticated
using (auth.uid() is not null);

create or replace view api.vw_viagens
with (security_invoker = true)
as
select
    viagem_id,
    titulo,
    status,
    inicio_em,
    fim_em,
    km_inicial,
    km_final,
    observacao,
    participantes,
    empresas_planejadas,
    criado_em,
    atualizado_em
from crm.viagens;

comment on view api.vw_viagens is
'Lista autenticada das fichas de viagem para o CRM.';

revoke all on api.vw_viagens from public, anon;
grant select on api.vw_viagens to authenticated, service_role;

create or replace function api.criar_viagem(
    p_titulo             text,
    p_inicio             date,
    p_fim                date,
    p_observacao         text default null,
    p_participantes      jsonb default '[]'::jsonb,
    p_clientes           jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, crm
as $$
declare
    v_viagem crm.viagens%rowtype;
begin
    if auth.uid() is null then
        raise exception 'É necessário entrar para registrar uma viagem.';
    end if;

    if nullif(trim(p_titulo), '') is null then
        raise exception 'Informe o nome da viagem.';
    end if;

    if p_inicio is null or p_fim is null then
        raise exception 'Informe as datas de início e final.';
    end if;

    if p_fim < p_inicio then
        raise exception 'A data final não pode ser anterior à data inicial.';
    end if;

    insert into crm.viagens (
        titulo,
        inicio_em,
        fim_em,
        observacao,
        participantes,
        empresas_planejadas
    ) values (
        trim(p_titulo),
        p_inicio::timestamptz,
        p_fim::timestamptz,
        nullif(trim(p_observacao), ''),
        case when jsonb_typeof(coalesce(p_participantes, '[]'::jsonb)) = 'array'
            then p_participantes else '[]'::jsonb end,
        case when jsonb_typeof(coalesce(p_clientes, '[]'::jsonb)) = 'array'
            then p_clientes else '[]'::jsonb end
    )
    returning * into v_viagem;

    return to_jsonb(v_viagem);
end;
$$;

revoke all on function api.criar_viagem(text, date, date, text, jsonb, jsonb)
    from public, anon;
grant execute on function api.criar_viagem(text, date, date, text, jsonb, jsonb)
    to authenticated, service_role;

commit;

notify pgrst, 'reload schema';
