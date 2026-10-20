-- ============================================================================
-- PROPOSTAS MHS - BIBLIOTECA DE FRASES PRONTAS PARA OBSERVACOES
-- Execute depois de 20260929_0045_validar_persistencia_local_catalogo_mhs.sql.
-- A biblioteca e independente das observacoes de cada proposta: ao inserir uma
-- frase, a interface a inclui no campo de observacoes ja persistido pela rotina
-- transacional existente.
-- ============================================================================

begin;

create table if not exists propostas_mhs.frases_prontas_observacoes (
  frase_pronta_id uuid primary key default gen_random_uuid(),
  conteudo text not null,
  ordem integer not null default 100,
  ativo boolean not null default true,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint frases_prontas_observacoes_conteudo_uidx unique (conteudo),
  constraint frases_prontas_observacoes_ordem_check check (ordem > 0),
  constraint frases_prontas_observacoes_conteudo_check check (length(trim(conteudo)) between 1 and 1000)
);

create index if not exists frases_prontas_observacoes_ativas_ordem_idx
  on propostas_mhs.frases_prontas_observacoes (ativo, ordem, criado_em);

alter table propostas_mhs.frases_prontas_observacoes enable row level security;
revoke all on propostas_mhs.frases_prontas_observacoes from public, anon, authenticated;

drop trigger if exists frases_prontas_observacoes_preencher_atualizacao
  on propostas_mhs.frases_prontas_observacoes;
create trigger frases_prontas_observacoes_preencher_atualizacao
before update on propostas_mhs.frases_prontas_observacoes
for each row execute function propostas_mhs.preencher_atualizacao();

insert into propostas_mhs.frases_prontas_observacoes (conteudo, ordem)
values
  ('Qualquer despesa não declarada na presente proposta correrá por conta do comprador.', 10),
  ('Os valores apresentados consideram as condições comerciais e o escopo desta proposta.', 20),
  ('Alterações de escopo, quantitativos ou especificações poderão exigir revisão comercial e de prazo.', 30),
  ('O fornecimento será realizado conforme as especificações técnicas aprovadas.', 40)
on conflict (conteudo) do nothing;

create or replace function api.listar_frases_prontas_observacoes_mhs()
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'frase_pronta_id', f.frase_pronta_id,
        'conteudo', f.conteudo,
        'ordem', f.ordem
      ) order by f.ordem, f.criado_em
    )
    from propostas_mhs.frases_prontas_observacoes f
    where f.ativo
  ), '[]'::jsonb);
end;
$$;

create or replace function api.salvar_frase_pronta_observacao_mhs(
  p_conteudo text,
  p_ordem integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_conteudo text := nullif(trim(p_conteudo), '');
  v_ordem integer;
  v_frase propostas_mhs.frases_prontas_observacoes%rowtype;
begin
  perform api.exigir_editor();

  if v_conteudo is null or length(v_conteudo) > 1000 then
    raise exception 'A frase deve ter entre 1 e 1000 caracteres.' using errcode = '22023';
  end if;

  v_ordem := coalesce(
    p_ordem,
    (select coalesce(max(ordem), 0) + 10 from propostas_mhs.frases_prontas_observacoes)
  );
  if v_ordem <= 0 then
    raise exception 'A ordem da frase deve ser maior que zero.' using errcode = '22023';
  end if;

  insert into propostas_mhs.frases_prontas_observacoes (
    conteudo, ordem, ativo, criado_por, atualizado_por
  ) values (
    v_conteudo, v_ordem, true, auth.uid(), auth.uid()
  ) on conflict (conteudo) do update
    set ativo = true,
        atualizado_por = auth.uid(),
        atualizado_em = now()
  returning * into v_frase;

  return jsonb_build_object(
    'frase_pronta_id', v_frase.frase_pronta_id,
    'conteudo', v_frase.conteudo,
    'ordem', v_frase.ordem
  );
end;
$$;

revoke all on function api.listar_frases_prontas_observacoes_mhs() from public, anon;
revoke all on function api.salvar_frase_pronta_observacao_mhs(text, integer) from public, anon;
grant execute on function api.listar_frases_prontas_observacoes_mhs() to authenticated;
grant execute on function api.salvar_frase_pronta_observacao_mhs(text, integer) to authenticated;

notify pgrst, 'reload schema';
commit;
