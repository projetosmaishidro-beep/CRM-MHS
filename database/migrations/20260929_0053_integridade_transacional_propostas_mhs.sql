-- ============================================================================
-- PROPOSTAS MHS - INTEGRIDADE TRANSACIONAL E REORDENACAO SEGURA
-- Execute depois de 20260929_0052_modelos_encerramento_propostas_mhs.sql.
-- Aditiva: preserva as APIs anteriores e oferece uma rota integral ao frontend.
-- ============================================================================

begin;

-- A ordem continua unica, mas a verificacao ocorre no commit. Isso permite
-- trocar 1 <-> 2 dentro da mesma sincronizacao sem uma colisao intermediaria.
alter table propostas_mhs.propostas_comissoes
  drop constraint if exists propostas_comissoes_ordem_uidx;
alter table propostas_mhs.propostas_comissoes
  add constraint propostas_comissoes_ordem_uidx
  unique (proposta_id, ordem) deferrable initially deferred;

create or replace function propostas_mhs.validar_total_comissoes_proposta_mhs()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_proposta_id uuid;
  v_total numeric;
begin
  v_proposta_id := case when tg_op = 'DELETE' then old.proposta_id else new.proposta_id end;
  select coalesce(sum(percentual_lucro), 0)
  into v_total
  from propostas_mhs.propostas_comissoes
  where proposta_id = v_proposta_id;

  if v_total > 100 then
    raise exception 'A distribuicao das comissoes nao pode ultrapassar 100%% do lucro.'
      using errcode = '23514', detail = format('total_percentual=%s', v_total);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists propostas_comissoes_validar_total on propostas_mhs.propostas_comissoes;
create constraint trigger propostas_comissoes_validar_total
after insert or update or delete on propostas_mhs.propostas_comissoes
deferrable initially deferred
for each row execute function propostas_mhs.validar_total_comissoes_proposta_mhs();

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
  v_resultado jsonb;
begin
  perform api.exigir_editor();
  v_salvo := api.salvar_proposta_transacional_mhs(
    p_proposta_id, p_dados, p_opcoes, p_grupo_opcoes, p_versao_esperada
  );
  perform api.sincronizar_local_cadastral_proposta_mhs(p_proposta_id, p_local);
  v_resultado := api.detalhar_proposta_mhs(p_proposta_id);
  return v_resultado || jsonb_build_object(
    'versao_persistencia', v_salvo -> 'versao_persistencia'
  );
end;
$$;

create or replace function api.criar_e_salvar_proposta_integral_mhs(
  p_criacao jsonb,
  p_dados jsonb,
  p_opcoes jsonb,
  p_grupo_opcoes jsonb,
  p_local jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_criada jsonb;
  v_proposta_id uuid;
begin
  perform api.exigir_editor();
  v_criada := api.criar_proposta_mhs(p_criacao);
  v_proposta_id := nullif(v_criada #>> '{proposta,proposta_id}', '')::uuid;
  if v_proposta_id is null then
    raise exception 'A criacao nao retornou o identificador da proposta.' using errcode = 'P0002';
  end if;
  return api.salvar_proposta_integral_mhs(
    v_proposta_id, p_dados, p_opcoes, p_grupo_opcoes, 0, p_local
  );
end;
$$;

-- Pagina os snapshots no servidor e isola uma proposta corrompida das demais.
-- Assim a tela não executa uma chamada HTTP por proposta nem oculta falhas.
create or replace function api.listar_snapshots_propostas_mhs(
  p_limite integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_linha record;
  v_resultado jsonb := '[]'::jsonb;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  if p_limite < 1 or p_limite > 100 or p_offset < 0 then
    raise exception 'Paginacao invalida.' using errcode = '22023';
  end if;

  for v_linha in
    select proposta_id, codigo
    from propostas_mhs.propostas
    where status <> 'CANCELADA'
    order by atualizado_em desc, proposta_id
    limit p_limite offset p_offset
  loop
    begin
      v_resultado := v_resultado || jsonb_build_array(jsonb_build_object(
        'ok', true,
        'proposta_id', v_linha.proposta_id,
        'codigo', v_linha.codigo,
        'snapshot', api.detalhar_proposta_mhs(v_linha.proposta_id)
      ));
    exception when others then
      v_resultado := v_resultado || jsonb_build_array(jsonb_build_object(
        'ok', false,
        'proposta_id', v_linha.proposta_id,
        'codigo', v_linha.codigo,
        'erro', sqlerrm
      ));
    end;
  end loop;
  return v_resultado;
end;
$$;

revoke all on function propostas_mhs.validar_total_comissoes_proposta_mhs()
from public, anon, authenticated;
revoke all on function api.salvar_proposta_integral_mhs(uuid, jsonb, jsonb, jsonb, bigint, jsonb)
from public, anon;
revoke all on function api.criar_e_salvar_proposta_integral_mhs(jsonb, jsonb, jsonb, jsonb, jsonb)
from public, anon;
revoke all on function api.listar_snapshots_propostas_mhs(integer, integer)
from public, anon;
grant execute on function api.salvar_proposta_integral_mhs(uuid, jsonb, jsonb, jsonb, bigint, jsonb)
to authenticated;
grant execute on function api.criar_e_salvar_proposta_integral_mhs(jsonb, jsonb, jsonb, jsonb, jsonb)
to authenticated;
grant execute on function api.listar_snapshots_propostas_mhs(integer, integer)
to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'propostas_comissoes_ordem_uidx'
      and conrelid = 'propostas_mhs.propostas_comissoes'::regclass
      and condeferrable and condeferred
  ) then
    raise exception 'A ordem das comissoes nao ficou adiavel.';
  end if;
  if to_regprocedure('api.salvar_proposta_integral_mhs(uuid,jsonb,jsonb,jsonb,bigint,jsonb)') is null
    or to_regprocedure('api.criar_e_salvar_proposta_integral_mhs(jsonb,jsonb,jsonb,jsonb,jsonb)') is null
    or to_regprocedure('api.listar_snapshots_propostas_mhs(integer,integer)') is null then
    raise exception 'As APIs de integridade da proposta nao foram instaladas.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
