-- ============================================================================
-- PROPOSTAS MHS - OPCOES COMERCIAIS NORMALIZADAS
-- Execute depois de 20260929_0036_responsaveis_comerciais_propostas_mhs.sql.
-- Mantem compatibilidade com propostas legadas e com o snapshot mhs_ui_v1.
-- ============================================================================

begin;

create table if not exists propostas_mhs.propostas_opcoes_comerciais (
  proposta_opcao_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  chave_externa text not null,
  ordem integer not null,
  titulo text not null,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_opcoes_chave_uidx unique (proposta_id, chave_externa),
  constraint propostas_opcoes_ordem_uidx unique (proposta_id, ordem),
  constraint propostas_opcoes_ordem_check check (ordem > 0),
  constraint propostas_opcoes_titulo_check check (length(trim(titulo)) > 0)
);

alter table propostas_mhs.propostas_grupos
  add column if not exists proposta_opcao_id uuid references propostas_mhs.propostas_opcoes_comerciais(proposta_opcao_id) on delete restrict;

create index if not exists propostas_grupos_opcao_ordem_idx
  on propostas_mhs.propostas_grupos (proposta_opcao_id, ordem);

-- Cada proposta existente recebe uma unica opcao principal; nenhum dado e perdido.
insert into propostas_mhs.propostas_opcoes_comerciais (proposta_id, chave_externa, ordem, titulo, criado_por, atualizado_por)
select p.proposta_id, 'opcao-principal', 1, '1. Dos produtos', p.criado_por, p.atualizado_por
from propostas_mhs.propostas p
where not exists (
  select 1 from propostas_mhs.propostas_opcoes_comerciais o where o.proposta_id = p.proposta_id
);

update propostas_mhs.propostas_grupos g
set proposta_opcao_id = o.proposta_opcao_id
from propostas_mhs.propostas_opcoes_comerciais o
where o.proposta_id = g.proposta_id
  and o.ordem = 1
  and g.proposta_opcao_id is null;

alter table propostas_mhs.propostas_opcoes_comerciais enable row level security;
revoke all on propostas_mhs.propostas_opcoes_comerciais from public, anon, authenticated;

drop trigger if exists propostas_opcoes_preencher_atualizacao on propostas_mhs.propostas_opcoes_comerciais;
create trigger propostas_opcoes_preencher_atualizacao before update on propostas_mhs.propostas_opcoes_comerciais
for each row execute function propostas_mhs.preencher_atualizacao();

-- Sincroniza as opcoes depois que a rotina existente salvou os grupos e itens.
-- A chave externa e o ID estavel da interface; o UUID continua exclusivamente interno ao banco.
create or replace function api.sincronizar_opcoes_comerciais_proposta_mhs(
  p_proposta_id uuid,
  p_opcoes jsonb,
  p_grupo_opcoes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_opcao jsonb;
  v_grupo jsonb;
  v_ordem integer := 0;
  v_chave text;
  v_opcao_id uuid;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_opcoes, '[]'::jsonb)) <> 'array' then
    raise exception 'opcoes deve ser uma lista.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_grupo_opcoes, '[]'::jsonb)) <> 'array' then
    raise exception 'grupo_opcoes deve ser uma lista.' using errcode = '22023';
  end if;
  if not exists (select 1 from propostas_mhs.propostas where proposta_id = p_proposta_id for update) then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  for v_opcao in select value from jsonb_array_elements(p_opcoes) loop
    v_ordem := v_ordem + 1;
    v_chave := nullif(trim(coalesce(v_opcao ->> 'id', v_opcao ->> 'chave_externa')), '');
    if v_chave is null then
      raise exception 'Cada opcao precisa de um identificador estavel.' using errcode = '22023';
    end if;
    insert into propostas_mhs.propostas_opcoes_comerciais (
      proposta_id, chave_externa, ordem, titulo, criado_por, atualizado_por
    ) values (
      p_proposta_id, v_chave,
      coalesce(nullif(v_opcao ->> 'order', '')::integer, v_ordem),
      coalesce(nullif(trim(v_opcao ->> 'title'), ''), case when v_ordem = 1 then '1. Dos produtos' else '1.' || (v_ordem - 1)::text || ' Dos produtos' end),
      auth.uid(), auth.uid()
    ) on conflict (proposta_id, chave_externa) do update
      set ordem = excluded.ordem,
          titulo = excluded.titulo,
          atualizado_por = auth.uid(),
          atualizado_em = now();
  end loop;

  if v_ordem = 0 then
    raise exception 'A proposta precisa de ao menos uma opcao comercial.' using errcode = '22023';
  end if;

  for v_grupo in select value from jsonb_array_elements(p_grupo_opcoes) loop
    v_chave := nullif(trim(coalesce(v_grupo ->> 'commercialOptionId', v_grupo ->> 'chave_externa')), '');
    if v_chave is null then continue; end if;
    select proposta_opcao_id into v_opcao_id
    from propostas_mhs.propostas_opcoes_comerciais
    where proposta_id = p_proposta_id and chave_externa = v_chave;
    if v_opcao_id is null then
      raise exception 'Opcao comercial % nao pertence a proposta.', v_chave using errcode = '22023';
    end if;
    update propostas_mhs.propostas_grupos
    set proposta_opcao_id = v_opcao_id,
        atualizado_por = auth.uid(),
        atualizado_em = now()
    where proposta_id = p_proposta_id
      and ordem = coalesce(nullif(v_grupo ->> 'order', '')::integer, nullif(v_grupo ->> 'ordem', '')::integer);
  end loop;

  -- Grupos sem metadado pertencem a opcao principal para preservar legados.
  update propostas_mhs.propostas_grupos g
  set proposta_opcao_id = o.proposta_opcao_id
  from propostas_mhs.propostas_opcoes_comerciais o
  where g.proposta_id = p_proposta_id
    and g.proposta_opcao_id is null
    and o.proposta_id = p_proposta_id
    and o.ordem = 1;

  perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'ATUALIZADA', 'Opcoes comerciais sincronizadas');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.detalhar_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_snapshot jsonb;
  v_responsavel jsonb;
  v_grupos jsonb;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  v_snapshot := propostas_mhs.montar_snapshot_proposta_com_grupos(p_proposta_id);
  if v_snapshot is null then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  select coalesce(jsonb_agg(e.value || jsonb_build_object('chave_opcao_externa', o.chave_externa) order by e.ordinality), '[]'::jsonb)
  into v_grupos
  from jsonb_array_elements(coalesce(v_snapshot -> 'grupos', '[]'::jsonb)) with ordinality e(value, ordinality)
  left join propostas_mhs.propostas_grupos g
    on g.proposta_id = p_proposta_id and g.ordem = nullif(e.value ->> 'ordem', '')::integer
  left join propostas_mhs.propostas_opcoes_comerciais o on o.proposta_opcao_id = g.proposta_opcao_id;

  select jsonb_build_object('responsavel_nome', coalesce(e.nome, u.email, 'Responsavel nao identificado'), 'responsavel_email', u.email)
  into v_responsavel
  from propostas_mhs.propostas p
  left join auth.users u on u.id = p.atualizado_por
  left join cadastro.equipe e on e.usuario_id = p.atualizado_por and e.ativo
  where p.proposta_id = p_proposta_id;

  v_snapshot := jsonb_set(v_snapshot, '{grupos}', v_grupos, true);
  v_snapshot := jsonb_set(v_snapshot, '{proposta}', coalesce(v_snapshot -> 'proposta', '{}'::jsonb) || coalesce(v_responsavel, '{}'::jsonb), true);
  return v_snapshot || jsonb_build_object(
    'opcoes_comerciais', coalesce((
      select jsonb_agg(jsonb_build_object('id', chave_externa, 'order', ordem, 'title', titulo) order by ordem)
      from propostas_mhs.propostas_opcoes_comerciais where proposta_id = p_proposta_id
    ), '[]'::jsonb),
    'arquivos', coalesce((select jsonb_agg(to_jsonb(a) order by a.enviado_em, a.nome_original) from propostas_mhs.arquivos_proposta a where a.proposta_id = p_proposta_id and a.estado = 'ATIVO'), '[]'::jsonb)
  );
end;
$$;

revoke all on function api.sincronizar_opcoes_comerciais_proposta_mhs(uuid, jsonb, jsonb) from public, anon;
grant execute on function api.sincronizar_opcoes_comerciais_proposta_mhs(uuid, jsonb, jsonb) to authenticated;
grant execute on function api.detalhar_proposta_mhs(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
