-- ============================================================================
-- SEGURANCA - LEITURA RESTRITA A MEMBROS E ESCRITA SOMENTE POR RPC
-- Execute depois de 20260930_0056_impedir_retries_checkpoint_propostas_mhs.sql.
-- Contexto: o signup publico esteve aberto, entao qualquer conta autenticada
-- (mesmo fora de cadastro.equipe) lia viagens, visitas, necessidades, eventos,
-- despesas e a equipe, e podia subir arquivos no bucket eventos-anexos.
-- ============================================================================

begin;

-- 1. Leitura das tabelas base apenas para membros ativos da equipe ------------

drop policy if exists app_le_viagens on crm.viagens;
drop policy if exists viagens_crm_le_membros on crm.viagens;
create policy viagens_crm_le_membros on crm.viagens
  for select to authenticated using ((select api.eh_membro()));

drop policy if exists app_le_visitas on crm.visitas;
drop policy if exists visitas_crm_le_membros on crm.visitas;
create policy visitas_crm_le_membros on crm.visitas
  for select to authenticated using ((select api.eh_membro()));

drop policy if exists app_le_necessidades on crm.necessidades;
drop policy if exists necessidades_crm_le_membros on crm.necessidades;
create policy necessidades_crm_le_membros on crm.necessidades
  for select to authenticated using ((select api.eh_membro()));

drop policy if exists app_le_eventos on crm.eventos;
drop policy if exists eventos_crm_le_membros on crm.eventos;
create policy eventos_crm_le_membros on crm.eventos
  for select to authenticated using ((select api.eh_membro()));

drop policy if exists app_le_despesas on crm.despesas;
drop policy if exists despesas_crm_le_membros on crm.despesas;
create policy despesas_crm_le_membros on crm.despesas
  for select to authenticated using ((select api.eh_membro()));

-- api.eh_membro() e security definer e le cadastro.equipe como owner, entao
-- nao ha recursao de RLS nesta policy.
drop policy if exists equipe_le_perfis on cadastro.equipe;
drop policy if exists equipe_le_membros on cadastro.equipe;
create policy equipe_le_membros on cadastro.equipe
  for select to authenticated using ((select api.eh_membro()) and ativo = true);

-- 2. Storage: remove o upload aberto no bucket legado eventos-anexos -----------
-- O frontend usa somente crm-anexos (envio/exclusao por editor, leitura por
-- membro). A leitura de eventos-anexos continua restrita a membros.

drop policy if exists "Equipe pode subir anexos de eventos" on storage.objects;

-- 3. Views do schema api: somente leitura ---------------------------------------

do $$
declare
  v record;
begin
  for v in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'api' and c.relkind in ('v', 'm')
  loop
    execute format('revoke insert, update, delete, truncate, references, trigger on api.%I from public, anon, authenticated', v.relname);
  end loop;
end;
$$;

-- 4. RPCs: nada executavel por anon/public --------------------------------------
-- Preserva o EXECUTE explicito do authenticated nas funcoes que ja o tinham
-- antes de retirar o PUBLIC, para nao reabrir funcoes legadas bloqueadas.

do $$
declare
  f record;
begin
  for f in
    select p.oid::regprocedure as assinatura
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'api'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  loop
    execute format('grant execute on function %s to authenticated', f.assinatura);
  end loop;
end;
$$;

revoke all on all functions in schema api from public, anon;

alter default privileges for role postgres in schema api
  revoke execute on functions from public, anon;

-- registrar_auditoria nao valida papel e so e chamada por outras RPCs
-- security definer (executadas como postgres). Sem acesso direto pela API.
revoke all on function api.registrar_auditoria(text, uuid, text, jsonb) from authenticated;

-- 5. Validacao -------------------------------------------------------------------

do $$
declare
  v_qtd integer;
begin
  select count(*) into v_qtd
  from pg_policies
  where schemaname in ('cadastro', 'crm', 'mapa', 'propostas_mhs')
    and cmd = 'SELECT'
    and coalesce(qual, '') not ilike '%eh_membro%';
  if v_qtd > 0 then
    raise exception 'Ainda existem % policies de leitura sem api.eh_membro().', v_qtd;
  end if;

  select count(*) into v_qtd
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects'
    and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
    and coalesce(qual, '') || coalesce(with_check, '') not ilike '%eh_editor%'
    and coalesce(qual, '') || coalesce(with_check, '') not ilike '%eh_admin%';
  if v_qtd > 0 then
    raise exception 'Ainda existem % policies de escrita no storage sem papel.', v_qtd;
  end if;

  select count(*) into v_qtd
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'api' and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_qtd > 0 then
    raise exception 'Ainda existem % funcoes de api executaveis por anon.', v_qtd;
  end if;

  select count(*) into v_qtd
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'api' and c.relkind = 'v'
    and (has_table_privilege('authenticated', c.oid, 'INSERT')
      or has_table_privilege('authenticated', c.oid, 'UPDATE')
      or has_table_privilege('authenticated', c.oid, 'DELETE'));
  if v_qtd > 0 then
    raise exception 'Ainda existem % views de api com escrita para authenticated.', v_qtd;
  end if;

  if not has_function_privilege('authenticated', 'api.eh_membro()', 'EXECUTE')
     or not has_function_privilege('authenticated', 'api.criar_visita(jsonb)', 'EXECUTE') then
    raise exception 'authenticated perdeu EXECUTE em RPCs usadas pelo frontend.';
  end if;
end;
$$;

commit;
