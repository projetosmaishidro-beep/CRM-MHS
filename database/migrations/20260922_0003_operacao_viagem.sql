-- Blocos operacionais da ficha de viagem.
-- Execute após 20260920_0002_api_operacional_supabase.sql.
-- A alteração é aditiva: não remove nem altera registros já existentes.

begin;

alter table crm.viagens
  add column if not exists notas jsonb not null default '[]'::jsonb;

comment on column crm.viagens.notas is
'Blocos cronológicos de observações da viagem, com autor e data de registro.';

create or replace view api.vw_viagens as
select viagem_id, titulo, status, inicio_em, fim_em, km_inicial, km_final,
       observacao, participantes, empresas_planejadas, paradas,
       odometro_registros, anexos, notas, criado_por, criado_em, atualizado_em
from crm.viagens;

create or replace function api.atualizar_viagem(p_viagem_id uuid, p_dados jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, api, crm
as $$
declare v_status text;
begin
  perform api.exigir_editor();
  v_status := case upper(coalesce(p_dados ->> 'status', ''))
    when 'PLANEJADA' then 'PLANEJADA' when 'EM ANDAMENTO' then 'EM_ANDAMENTO'
    when 'EM_ANDAMENTO' then 'EM_ANDAMENTO' when 'CONCLUIDA' then 'CONCLUIDA'
    when 'CONCLUÍDA' then 'CONCLUIDA' when 'CANCELADA' then 'CANCELADA' else null end;

  update crm.viagens set
    status = coalesce(v_status, status),
    observacao = coalesce(nullif(trim(coalesce(p_dados ->> 'notes', p_dados ->> 'objective')), ''), observacao),
    participantes = coalesce(p_dados -> 'participants', participantes),
    empresas_planejadas = coalesce(p_dados -> 'clients', empresas_planejadas),
    paradas = coalesce(p_dados -> 'stops', paradas),
    odometro_registros = coalesce(p_dados -> 'odometerRecords', odometro_registros),
    anexos = coalesce(p_dados -> 'attachments', anexos),
    notas = case
      when p_dados ? 'noteBlocks' and jsonb_typeof(p_dados -> 'noteBlocks') = 'array'
        then p_dados -> 'noteBlocks'
      else notas
    end,
    km_inicial = coalesce(nullif(p_dados ->> 'startKm', '')::numeric, km_inicial),
    km_final = coalesce(nullif(p_dados ->> 'endKm', '')::numeric, km_final),
    atualizado_em = now()
  where viagem_id = p_viagem_id;

  if not found then raise exception 'Viagem nao encontrada.' using errcode = 'P0002'; end if;
  perform api.registrar_auditoria('VIAGEM', p_viagem_id, 'ATUALIZADA');
  return (select to_jsonb(x) from api.vw_viagens x where x.viagem_id = p_viagem_id);
end;
$$;

notify pgrst, 'reload schema';
commit;
