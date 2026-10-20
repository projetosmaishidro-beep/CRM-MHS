-- ============================================================================
-- PROPOSTAS MHS - CONFLITOS HTTP SEM RETRY INTERNO DO POSTGREST
-- Execute depois de 20260930_0055_checkpoints_salvamento_propostas_mhs.sql.
-- Converte conflitos esperados em HTTP 409 e evita ciclos de retry por 40001.
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
  v_erro text;
  v_detalhe text;
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

  if not pg_try_advisory_xact_lock(hashtextextended(p_proposta_id::text, 0)) then
    raise sqlstate 'PT409'
      using message = 'Ja existe um checkpoint em andamento para esta proposta.',
            detail = 'A gravacao concorrente foi recusada sem repeticao automatica.',
            hint = 'Aguarde a confirmacao do checkpoint atual antes de tentar novamente.';
  end if;

  perform api.sincronizar_local_cadastral_proposta_mhs(p_proposta_id, p_local);

  begin
    v_salvo := api.salvar_proposta_transacional_mhs(
      p_proposta_id, p_dados, p_opcoes, p_grupo_opcoes, p_versao_esperada
    );
  exception
    when serialization_failure then
      get stacked diagnostics
        v_erro = message_text,
        v_detalhe = pg_exception_detail;
      raise sqlstate 'PT409'
        using message = coalesce(nullif(v_erro, ''), 'A proposta foi atualizada em outra operacao.'),
              detail = coalesce(nullif(v_detalhe, ''), 'A versao recebida nao corresponde a versao atual.'),
              hint = 'Recarregue a proposta antes de confirmar novamente.';
  end;

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

  if position('PT409' in v_definicao) = 0
    or position('serialization_failure' in v_definicao) = 0
    or position('pg_try_advisory_xact_lock' in v_definicao) = 0 then
    raise exception 'A protecao contra retries de conflito nao foi instalada.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
