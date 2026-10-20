-- ============================================================================
-- PROPOSTAS MHS - CORRECAO DOS TRIGGERS DA ESTRUTURA HIERARQUICA
-- Execute depois de 20260929_0053_integridade_transacional_propostas_mhs.sql.
-- Separa validacoes de tabelas distintas para que NEW use somente campos reais.
-- ============================================================================

begin;

create or replace function propostas_mhs.validar_modulo_item_composicao_mhs()
returns trigger
language plpgsql
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_grupo_modulo uuid;
begin
  if new.proposta_composicao_modulo_id is null then
    return new;
  end if;

  select proposta_grupo_id
  into v_grupo_modulo
  from propostas_mhs.propostas_composicao_modulos
  where proposta_composicao_modulo_id = new.proposta_composicao_modulo_id;

  if v_grupo_modulo is null
    or new.proposta_grupo_id is distinct from v_grupo_modulo then
    raise exception 'O modulo deve pertencer ao mesmo grupo comercial do item.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create or replace function propostas_mhs.validar_pai_item_composicao_mhs()
returns trigger
language plpgsql
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_item_pai uuid;
begin
  if new.proposta_item_composicao_pai_id is null then
    return new;
  end if;

  if new.proposta_item_composicao_pai_id = new.proposta_item_composicao_id then
    raise exception 'Um subitem nao pode ser pai de si mesmo.'
      using errcode = '23514';
  end if;

  select proposta_item_id
  into v_item_pai
  from propostas_mhs.propostas_itens_composicao
  where proposta_item_composicao_id = new.proposta_item_composicao_pai_id;

  if v_item_pai is null or v_item_pai <> new.proposta_item_id then
    raise exception 'O subitem-pai deve pertencer ao mesmo item-cabeca.'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

drop trigger if exists propostas_itens_validar_modulo_composicao
  on propostas_mhs.propostas_itens;
create trigger propostas_itens_validar_modulo_composicao
before insert or update of proposta_composicao_modulo_id, proposta_grupo_id
on propostas_mhs.propostas_itens
for each row execute function propostas_mhs.validar_modulo_item_composicao_mhs();

drop trigger if exists propostas_itens_composicao_validar_pai
  on propostas_mhs.propostas_itens_composicao;
create trigger propostas_itens_composicao_validar_pai
before insert or update of proposta_item_composicao_pai_id, proposta_item_id
on propostas_mhs.propostas_itens_composicao
for each row execute function propostas_mhs.validar_pai_item_composicao_mhs();

revoke all on function propostas_mhs.validar_modulo_item_composicao_mhs()
from public, anon, authenticated;
revoke all on function propostas_mhs.validar_pai_item_composicao_mhs()
from public, anon, authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'propostas_mhs.propostas_itens'::regclass
      and t.tgname = 'propostas_itens_validar_modulo_composicao'
      and t.tgfoid = 'propostas_mhs.validar_modulo_item_composicao_mhs()'::regprocedure
      and not t.tgisinternal
  ) then
    raise exception 'O trigger de validacao do modulo nao foi corrigido.';
  end if;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'propostas_mhs.propostas_itens_composicao'::regclass
      and t.tgname = 'propostas_itens_composicao_validar_pai'
      and t.tgfoid = 'propostas_mhs.validar_pai_item_composicao_mhs()'::regprocedure
      and not t.tgisinternal
  ) then
    raise exception 'O trigger de validacao do subitem-pai nao foi corrigido.';
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
