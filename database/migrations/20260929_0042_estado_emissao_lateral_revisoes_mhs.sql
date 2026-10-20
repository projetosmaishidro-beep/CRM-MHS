-- ============================================================================
-- PROPOSTAS MHS - ESTADO OPERACIONAL FORA DO SNAPSHOT IMUTAVEL
-- Execute depois de 20260929_0041_corrigir_operacoes_historico_rascunho_mhs.sql.
-- Revisoes permanecem fotografias imutaveis; o ciclo de emissao fica lateral.
-- ============================================================================

begin;

create table if not exists propostas_mhs.propostas_revisoes_emissao (
  revisao_id uuid primary key,
  proposta_id uuid not null,
  chave_idempotencia text,
  estado text not null default 'PREPARANDO',
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_revisoes_emissao_revisao_fk
    foreign key (revisao_id, proposta_id)
    references propostas_mhs.propostas_revisoes (revisao_id, proposta_id) on delete restrict,
  constraint propostas_revisoes_emissao_estado_check
    check (estado in ('PREPARANDO', 'PDF_ENVIADO', 'CONFIRMADA', 'FALHOU'))
);

create unique index if not exists propostas_revisoes_emissao_idempotencia_uidx
  on propostas_mhs.propostas_revisoes_emissao (proposta_id, chave_idempotencia)
  where chave_idempotencia is not null;

alter table propostas_mhs.propostas_revisoes_emissao enable row level security;
revoke all on propostas_mhs.propostas_revisoes_emissao from public, anon, authenticated;

drop trigger if exists propostas_revisoes_emissao_preencher_atualizacao
  on propostas_mhs.propostas_revisoes_emissao;
create trigger propostas_revisoes_emissao_preencher_atualizacao
before update on propostas_mhs.propostas_revisoes_emissao
for each row execute function propostas_mhs.preencher_atualizacao();

create or replace function api.criar_revisao_idempotente_mhs(
  p_proposta_id uuid,
  p_tipo text default 'REVISAO',
  p_motivo text default null,
  p_chave_idempotencia text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_revisao propostas_mhs.propostas_revisoes%rowtype;
  v_chave text := nullif(trim(p_chave_idempotencia), '');
begin
  perform api.exigir_editor();
  perform 1 from propostas_mhs.propostas
  where proposta_id = p_proposta_id and numero_sequencial is not null
  for update;
  if not found then
    raise exception 'A proposta precisa receber numeracao antes da revisao.' using errcode = '55000';
  end if;

  if v_chave is not null then
    select r.* into v_revisao
    from propostas_mhs.propostas_revisoes_emissao e
    join propostas_mhs.propostas_revisoes r on r.revisao_id = e.revisao_id
    where e.proposta_id = p_proposta_id and e.chave_idempotencia = v_chave;
    if found then
      update propostas_mhs.propostas_revisoes_emissao
      set estado = case when estado = 'FALHOU' then 'PREPARANDO' else estado end
      where revisao_id = v_revisao.revisao_id;
      return to_jsonb(v_revisao);
    end if;
  end if;

  select * into v_revisao
  from propostas_mhs.criar_revisao_proposta(p_proposta_id, p_tipo, p_motivo);

  insert into propostas_mhs.propostas_revisoes_emissao (
    revisao_id, proposta_id, chave_idempotencia, estado, criado_por, atualizado_por
  ) values (
    v_revisao.revisao_id, p_proposta_id, v_chave, 'PREPARANDO', auth.uid(), auth.uid()
  );
  return to_jsonb(v_revisao);
end;
$$;

create or replace function api.marcar_estado_revisao_mhs(
  p_proposta_id uuid,
  p_revisao_id uuid,
  p_estado text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare v_estado text := upper(trim(p_estado)); v_registro propostas_mhs.propostas_revisoes_emissao%rowtype;
begin
  perform api.exigir_editor();
  if v_estado not in ('PREPARANDO', 'PDF_ENVIADO', 'CONFIRMADA', 'FALHOU') then
    raise exception 'Estado de emissao invalido.' using errcode = '22023';
  end if;
  if v_estado in ('PDF_ENVIADO', 'CONFIRMADA') and not exists (
    select 1 from propostas_mhs.arquivos_proposta a
    join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
    where a.proposta_id = p_proposta_id and a.revisao_id = p_revisao_id
      and a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO' and a.tamanho_bytes > 0
  ) then
    raise exception 'O PDF da revisao nao esta confirmado no bucket.' using errcode = '55000';
  end if;
  update propostas_mhs.propostas_revisoes_emissao
  set estado = v_estado
  where proposta_id = p_proposta_id and revisao_id = p_revisao_id
  returning * into v_registro;
  if not found then
    raise exception 'Controle de emissao da revisao nao encontrado.' using errcode = 'P0002';
  end if;
  return to_jsonb(v_registro);
end;
$$;

revoke all on function api.criar_revisao_idempotente_mhs(uuid, text, text, text) from public, anon;
revoke all on function api.marcar_estado_revisao_mhs(uuid, uuid, text) from public, anon;
grant execute on function api.criar_revisao_idempotente_mhs(uuid, text, text, text) to authenticated;
grant execute on function api.marcar_estado_revisao_mhs(uuid, uuid, text) to authenticated;

notify pgrst, 'reload schema';
commit;
