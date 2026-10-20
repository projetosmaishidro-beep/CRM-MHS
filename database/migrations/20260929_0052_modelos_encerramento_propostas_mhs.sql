-- ============================================================================
-- PROPOSTAS MHS - BIBLIOTECA COMPARTILHADA DE ASSINATURAS E RODAPES
-- Execute depois de 20260929_0051_validacao_fiscal_calculos_proposta_mhs.sql.
-- Cada modelo e reutilizavel por todos os usuarios autorizados do modulo.
-- ============================================================================

begin;

create table if not exists propostas_mhs.modelos_encerramento_proposta (
  modelo_encerramento_id uuid primary key default gen_random_uuid(),
  nome text not null,
  dados jsonb not null default '{}'::jsonb,
  criado_por uuid not null references auth.users(id) on delete restrict,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint modelos_encerramento_proposta_nome_criador_uidx unique (criado_por, nome),
  constraint modelos_encerramento_proposta_nome_check check (length(trim(nome)) between 1 and 120),
  constraint modelos_encerramento_proposta_dados_check check (jsonb_typeof(dados) = 'object')
);

create index if not exists modelos_encerramento_proposta_nome_idx
  on propostas_mhs.modelos_encerramento_proposta (nome, criado_em);

alter table propostas_mhs.modelos_encerramento_proposta enable row level security;
revoke all on propostas_mhs.modelos_encerramento_proposta from public, anon, authenticated;

drop trigger if exists modelos_encerramento_proposta_preencher_atualizacao
  on propostas_mhs.modelos_encerramento_proposta;
create trigger modelos_encerramento_proposta_preencher_atualizacao
before update on propostas_mhs.modelos_encerramento_proposta
for each row execute function propostas_mhs.preencher_atualizacao();

create or replace function api.listar_modelos_encerramento_proposta_mhs()
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
    select jsonb_agg(jsonb_build_object(
      'modelo_encerramento_id', m.modelo_encerramento_id,
      'nome', m.nome,
      'dados', m.dados,
      'criado_por_nome', coalesce(e.nome, au.email)
    ) order by m.nome, m.criado_em)
    from propostas_mhs.modelos_encerramento_proposta m
    left join cadastro.equipe e on e.usuario_id = m.criado_por
    left join auth.users au on au.id = m.criado_por
  ), '[]'::jsonb);
end;
$$;

create or replace function api.salvar_modelo_encerramento_proposta_mhs(
  p_nome text,
  p_dados jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_nome text := nullif(trim(p_nome), '');
  v_dados jsonb := coalesce(p_dados, '{}'::jsonb);
  v_modelo propostas_mhs.modelos_encerramento_proposta%rowtype;
begin
  perform api.exigir_editor();

  if v_nome is null or length(v_nome) > 120 then
    raise exception 'O nome do modelo deve ter entre 1 e 120 caracteres.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_dados) <> 'object' then
    raise exception 'Os dados do modelo devem ser um objeto.' using errcode = '22023';
  end if;
  if length(coalesce(v_dados ->> 'saudacao', '')) > 160
    or length(coalesce(v_dados ->> 'empresa', '')) > 160
    or length(coalesce(v_dados ->> 'signatario', '')) > 160
    or length(coalesce(v_dados ->> 'cargo', '')) > 160 then
    raise exception 'Os campos da assinatura aceitam no maximo 160 caracteres.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(v_dados -> 'rodape_linhas', '[]'::jsonb)) <> 'array'
    or jsonb_array_length(coalesce(v_dados -> 'rodape_linhas', '[]'::jsonb)) > 10 then
    raise exception 'O rodape deve possuir ate 10 linhas.' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_array_elements_text(coalesce(v_dados -> 'rodape_linhas', '[]'::jsonb)) linha where length(linha) > 240) then
    raise exception 'Cada linha do rodape aceita no maximo 240 caracteres.' using errcode = '22023';
  end if;

  insert into propostas_mhs.modelos_encerramento_proposta (nome, dados, criado_por, atualizado_por)
  values (v_nome, v_dados, auth.uid(), auth.uid())
  on conflict (criado_por, nome) do update
    set dados = excluded.dados,
        atualizado_por = auth.uid(),
        atualizado_em = now()
  returning * into v_modelo;

  return jsonb_build_object(
    'modelo_encerramento_id', v_modelo.modelo_encerramento_id,
    'nome', v_modelo.nome,
    'dados', v_modelo.dados,
    'criado_por_nome', (select coalesce(e.nome, au.email) from auth.users au left join cadastro.equipe e on e.usuario_id = au.id where au.id = v_modelo.criado_por)
  );
end;
$$;

revoke all on function api.listar_modelos_encerramento_proposta_mhs() from public, anon;
revoke all on function api.salvar_modelo_encerramento_proposta_mhs(text, jsonb) from public, anon;
grant execute on function api.listar_modelos_encerramento_proposta_mhs() to authenticated;
grant execute on function api.salvar_modelo_encerramento_proposta_mhs(text, jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
