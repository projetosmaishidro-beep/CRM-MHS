-- ============================================================================
-- PROPOSTAS MHS - DISTRIBUICAO DE COMISSOES POR DESTINO
-- Execute depois de 20260929_0049_validar_estrutura_hierarquica_composicoes_mhs.sql.
-- Os destinos sao texto livre: fundo comercial, colaborador, representante etc.
-- ============================================================================

begin;

create table if not exists propostas_mhs.propostas_comissoes (
  proposta_comissao_id uuid primary key default gen_random_uuid(),
  proposta_id uuid not null references propostas_mhs.propostas(proposta_id) on delete cascade,
  chave_externa text not null,
  ordem integer not null,
  destino text not null,
  percentual_lucro numeric(9,4) not null,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint propostas_comissoes_chave_uidx unique (proposta_id, chave_externa),
  constraint propostas_comissoes_ordem_uidx unique (proposta_id, ordem),
  constraint propostas_comissoes_destino_check check (length(trim(destino)) between 1 and 120),
  constraint propostas_comissoes_percentual_check check (percentual_lucro >= 0)
);

create index if not exists propostas_comissoes_proposta_ordem_idx
  on propostas_mhs.propostas_comissoes (proposta_id, ordem);

alter table propostas_mhs.propostas_comissoes enable row level security;
revoke all on propostas_mhs.propostas_comissoes from public, anon, authenticated;

drop trigger if exists propostas_comissoes_preencher_atualizacao on propostas_mhs.propostas_comissoes;
create trigger propostas_comissoes_preencher_atualizacao
before update on propostas_mhs.propostas_comissoes
for each row execute function propostas_mhs.preencher_atualizacao();

create or replace function propostas_mhs.sincronizar_comissoes_do_snapshot_mhs()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_comissoes jsonb := new.dados_adicionais #> '{mhs_ui_v1,commissionAllocations}';
  v_comissao jsonb;
  v_chave text;
  v_destino text;
  v_percentual numeric;
  v_ordem integer := 0;
begin
  -- Propostas legadas nao possuem rateio e continuam validas ate a primeira edicao.
  if v_comissoes is null then
    return new;
  end if;
  if jsonb_typeof(v_comissoes) <> 'array' then
    raise exception 'commissionAllocations deve ser uma lista.' using errcode = '22023';
  end if;

  delete from propostas_mhs.propostas_comissoes c
  where c.proposta_id = new.proposta_id
    and not exists (
      select 1
      from jsonb_array_elements(v_comissoes) item
      where nullif(trim(item ->> 'id'), '') = c.chave_externa
    );

  for v_comissao in select value from jsonb_array_elements(v_comissoes) loop
    v_ordem := v_ordem + 1;
    v_chave := nullif(trim(v_comissao ->> 'id'), '');
    v_destino := nullif(trim(v_comissao ->> 'destination'), '');
    v_percentual := coalesce(nullif(v_comissao ->> 'percentage', '')::numeric, 0);
    if v_chave is null or v_destino is null then
      raise exception 'Cada comissao precisa de identificador e destino.' using errcode = '22023';
    end if;
    if v_percentual < 0 then
      raise exception 'O percentual da comissao nao pode ser negativo.' using errcode = '22023';
    end if;

    insert into propostas_mhs.propostas_comissoes (
      proposta_id, chave_externa, ordem, destino, percentual_lucro, criado_por, atualizado_por
    ) values (
      new.proposta_id, v_chave, v_ordem, v_destino, v_percentual, auth.uid(), auth.uid()
    )
    on conflict (proposta_id, chave_externa) do update set
      ordem = excluded.ordem,
      destino = excluded.destino,
      percentual_lucro = excluded.percentual_lucro,
      atualizado_por = auth.uid(),
      atualizado_em = now();
  end loop;
  return new;
end;
$$;

drop trigger if exists propostas_sincronizar_comissoes_snapshot_mhs on propostas_mhs.propostas;
create trigger propostas_sincronizar_comissoes_snapshot_mhs
after insert or update of dados_adicionais on propostas_mhs.propostas
for each row execute function propostas_mhs.sincronizar_comissoes_do_snapshot_mhs();

revoke all on function propostas_mhs.sincronizar_comissoes_do_snapshot_mhs() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
