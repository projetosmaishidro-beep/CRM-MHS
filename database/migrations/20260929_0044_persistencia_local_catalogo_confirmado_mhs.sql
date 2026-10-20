-- ============================================================================
-- PROPOSTAS MHS - LOCAL CADASTRAL E HISTORICO DE CATALOGO CONFIRMADO
-- Execute depois de 20260929_0043_validar_estado_emissao_lateral_mhs.sql.
--
-- Aditiva: nao substitui rotinas existentes. O local e associado por uma API
-- idempotente; o historico global so e promovido na finalizacao da proposta.
-- ============================================================================

begin;

create or replace function api.sincronizar_local_cadastral_proposta_mhs(
  p_proposta_id uuid,
  p_local jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_empresa_id uuid;
  v_local_id uuid := nullif(p_local ->> 'local_obra_id', '')::uuid;
  v_nome text := nullif(trim(p_local ->> 'nome'), '');
  v_logradouro text := nullif(trim(p_local ->> 'logradouro'), '');
  v_municipio text := nullif(trim(p_local ->> 'municipio'), '');
  v_uf text := nullif(upper(trim(p_local ->> 'uf')), '');
  v_cep text := nullif(regexp_replace(coalesce(p_local ->> 'cep', ''), '\D', '', 'g'), '');
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_local, '{}'::jsonb)) <> 'object' then
    raise exception 'local deve ser um objeto.' using errcode = '22023';
  end if;
  if v_nome is null then
    raise exception 'Informe o nome do local cadastral.' using errcode = '22023';
  end if;
  if v_uf is not null and v_uf !~ '^[A-Z]{2}$' then
    raise exception 'UF do local invalida.' using errcode = '22023';
  end if;
  if v_cep is not null and v_cep !~ '^\d{8}$' then
    raise exception 'CEP do local invalido.' using errcode = '22023';
  end if;

  select empresa_id into v_empresa_id
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id
  for update;
  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  if v_local_id is not null then
    update propostas_mhs.locais_obra
    set nome = v_nome,
        logradouro = coalesce(v_logradouro, logradouro),
        municipio = coalesce(v_municipio, municipio),
        uf = coalesce(v_uf, uf),
        cep = coalesce(v_cep, cep),
        ativo = true,
        atualizado_por = auth.uid(),
        atualizado_em = now()
    where local_obra_id = v_local_id and empresa_id = v_empresa_id
    returning local_obra_id into v_local_id;
    if not found then
      raise exception 'O local informado nao pertence ao cliente da proposta.' using errcode = '23503';
    end if;
  else
    insert into propostas_mhs.locais_obra (
      empresa_id, nome, logradouro, municipio, uf, cep, ativo, criado_por, atualizado_por
    ) values (
      v_empresa_id, v_nome, v_logradouro, v_municipio, v_uf, v_cep, true, auth.uid(), auth.uid()
    ) on conflict (empresa_id, nome) do update
      set logradouro = coalesce(excluded.logradouro, propostas_mhs.locais_obra.logradouro),
          municipio = coalesce(excluded.municipio, propostas_mhs.locais_obra.municipio),
          uf = coalesce(excluded.uf, propostas_mhs.locais_obra.uf),
          cep = coalesce(excluded.cep, propostas_mhs.locais_obra.cep),
          ativo = true,
          atualizado_por = auth.uid(),
          atualizado_em = now()
    returning local_obra_id into v_local_id;
  end if;

  update propostas_mhs.propostas
  set local_obra_id = v_local_id,
      atualizado_por = auth.uid(),
      atualizado_em = now()
  where proposta_id = p_proposta_id;

  return jsonb_build_object('proposta_id', p_proposta_id, 'local_obra_id', v_local_id);
end;
$$;

create or replace function propostas_mhs.promover_historico_catalogo_na_finalizacao_mhs()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
begin
  if new.status = 'FINALIZADA' and old.status is distinct from 'FINALIZADA' then
    -- A rotina existente ignora itens sem item_catalogo_id e itens negociados
    -- com valores unitarios divergentes, preservando o catalogo mestre.
    perform propostas_mhs.sincronizar_historico_catalogo_da_proposta(new.proposta_id);
  end if;
  return new;
end;
$$;

drop trigger if exists propostas_promover_historico_catalogo_finalizacao
  on propostas_mhs.propostas;
create trigger propostas_promover_historico_catalogo_finalizacao
after update of status on propostas_mhs.propostas
for each row execute function propostas_mhs.promover_historico_catalogo_na_finalizacao_mhs();

revoke all on function api.sincronizar_local_cadastral_proposta_mhs(uuid, jsonb)
from public, anon;
grant execute on function api.sincronizar_local_cadastral_proposta_mhs(uuid, jsonb)
to authenticated;
revoke all on function propostas_mhs.promover_historico_catalogo_na_finalizacao_mhs()
from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
