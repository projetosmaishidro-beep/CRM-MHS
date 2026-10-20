-- ============================================================================
-- PROPOSTAS MHS - CHECKPOINTS DE SALVAMENTO E CONTENCAO POR PROPOSTA
-- Execute depois de 20260929_0054_corrigir_triggers_estrutura_composicoes_mhs.sql.
-- Aditiva: preserva o contrato das RPCs e impede gravacoes integrais concorrentes.
-- ============================================================================

begin;

create or replace function api.salvar_proposta_integral_mhs(
  p_proposta_id uuid,
  p_dados jsonb,
  p_opcoes jsonb,
  p_grupo_opcoes jsonb,
  p_versao_esperada bigint default 0,
  p_local jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_salvo jsonb;
begin
  perform api.exigir_editor();

  if p_proposta_id is null then
    raise exception 'O identificador da proposta e obrigatorio.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_dados, 'null'::jsonb)) <> 'object'
    or jsonb_typeof(coalesce(p_opcoes, 'null'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(p_grupo_opcoes, 'null'::jsonb)) <> 'array'
    or jsonb_typeof(coalesce(p_local, 'null'::jsonb)) <> 'object' then
    raise exception 'O checkpoint da proposta possui uma estrutura invalida.' using errcode = '22023';
  end if;
  if pg_column_size(p_dados) + pg_column_size(p_opcoes) + pg_column_size(p_grupo_opcoes) + pg_column_size(p_local) > 16777216 then
    raise exception 'O checkpoint ultrapassa o limite seguro de 16 MB.' using errcode = '54000';
  end if;

  -- Falha rapidamente se outra aba ou requisicao ainda estiver gravando a
  -- mesma proposta. Propostas diferentes continuam sendo salvas em paralelo.
  if not pg_try_advisory_xact_lock(hashtextextended(p_proposta_id::text, 0)) then
    raise exception 'Ja existe um checkpoint em andamento para esta proposta. Aguarde e tente novamente.'
      using errcode = '55P03';
  end if;

  -- O local precisa estar atualizado antes da leitura final feita pela funcao
  -- transacional. Assim eliminamos uma segunda montagem cara do snapshot.
  perform api.sincronizar_local_cadastral_proposta_mhs(p_proposta_id, p_local);
  v_salvo := api.salvar_proposta_transacional_mhs(
    p_proposta_id, p_dados, p_opcoes, p_grupo_opcoes, p_versao_esperada
  );
  return v_salvo;
end;
$$;

revoke all on function api.salvar_proposta_integral_mhs(uuid, jsonb, jsonb, jsonb, bigint, jsonb)
from public, anon;
grant execute on function api.salvar_proposta_integral_mhs(uuid, jsonb, jsonb, jsonb, bigint, jsonb)
to authenticated;

do $$
declare
  v_definicao text;
begin
  select pg_get_functiondef('api.salvar_proposta_integral_mhs(uuid,jsonb,jsonb,jsonb,bigint,jsonb)'::regprocedure)
  into v_definicao;

  if position('pg_try_advisory_xact_lock' in v_definicao) = 0 then
    raise exception 'A contencao por proposta nao foi instalada.';
  end if;
  if (length(v_definicao) - length(replace(v_definicao, 'detalhar_proposta_mhs', ''))) > 0 then
    raise exception 'A leitura integral duplicada ainda existe no checkpoint.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
