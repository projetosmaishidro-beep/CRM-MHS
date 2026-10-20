-- ============================================================================
-- PROPOSTAS MHS - INTEGRIDADE TRANSACIONAL PARA PRODUCAO
-- Execute depois de 20260929_0038_validar_opcoes_comerciais_mhs.sql.
-- Aditiva: preserva propostas, revisoes, arquivos, templates e historico.
-- ============================================================================

begin;

alter table propostas_mhs.propostas
  add column if not exists versao_edicao bigint not null default 0;

comment on column propostas_mhs.propostas.versao_edicao is
  'Versao otimista incrementada em cada salvamento completo; impede autosave obsoleto.';

alter table propostas_mhs.propostas_revisoes
  add column if not exists chave_idempotencia text,
  add column if not exists estado_emissao text not null default 'PREPARANDO';

alter table propostas_mhs.propostas_revisoes
  drop constraint if exists propostas_revisoes_estado_emissao_check;
alter table propostas_mhs.propostas_revisoes
  add constraint propostas_revisoes_estado_emissao_check
  check (estado_emissao in ('PREPARANDO', 'PDF_ENVIADO', 'CONFIRMADA', 'FALHOU'));

create unique index if not exists propostas_revisoes_idempotencia_uidx
  on propostas_mhs.propostas_revisoes (proposta_id, chave_idempotencia)
  where chave_idempotencia is not null;

create table if not exists propostas_mhs.conjuntos_reutilizaveis (
  conjunto_id uuid primary key default gen_random_uuid(),
  nome text not null,
  descricao text,
  proposta_origem_codigo text,
  modelo jsonb not null,
  cpmv_unitario numeric(19,4) not null default 0,
  cpmv_total numeric(19,4) not null default 0,
  preco_calculado numeric(19,4) not null default 0,
  ativo boolean not null default true,
  criado_por uuid references auth.users(id) on delete set null,
  atualizado_por uuid references auth.users(id) on delete set null,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  constraint conjuntos_reutilizaveis_nome_check check (length(trim(nome)) > 0),
  constraint conjuntos_reutilizaveis_modelo_check check (jsonb_typeof(modelo) = 'object'),
  constraint conjuntos_reutilizaveis_valores_check check (cpmv_unitario >= 0 and cpmv_total >= 0 and preco_calculado >= 0)
);

alter table propostas_mhs.conjuntos_reutilizaveis enable row level security;
revoke all on propostas_mhs.conjuntos_reutilizaveis from public, anon, authenticated;
drop policy if exists conjuntos_reutilizaveis_membros_leitura on propostas_mhs.conjuntos_reutilizaveis;
create policy conjuntos_reutilizaveis_membros_leitura
on propostas_mhs.conjuntos_reutilizaveis for select to authenticated
using (api.eh_membro());
grant usage on schema propostas_mhs to authenticated;
grant select on propostas_mhs.conjuntos_reutilizaveis to authenticated;
drop trigger if exists conjuntos_reutilizaveis_preencher_atualizacao on propostas_mhs.conjuntos_reutilizaveis;
create trigger conjuntos_reutilizaveis_preencher_atualizacao
before update on propostas_mhs.conjuntos_reutilizaveis
for each row execute function propostas_mhs.preencher_atualizacao();

create or replace view api.vw_conjuntos_reutilizaveis_mhs
with (security_invoker = true)
as
select conjunto_id, nome, descricao, proposta_origem_codigo, modelo,
       cpmv_unitario, cpmv_total, preco_calculado, atualizado_em
from propostas_mhs.conjuntos_reutilizaveis
where ativo;

revoke all on api.vw_conjuntos_reutilizaveis_mhs from public, anon;
grant select on api.vw_conjuntos_reutilizaveis_mhs to authenticated;

create or replace function api.salvar_conjunto_reutilizavel_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare v_registro propostas_mhs.conjuntos_reutilizaveis%rowtype;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_dados -> 'modelo', 'null'::jsonb)) <> 'object' then
    raise exception 'O modelo do conjunto deve ser um objeto.' using errcode = '22023';
  end if;
  insert into propostas_mhs.conjuntos_reutilizaveis (
    nome, descricao, proposta_origem_codigo, modelo, cpmv_unitario,
    cpmv_total, preco_calculado, criado_por, atualizado_por
  ) values (
    nullif(trim(p_dados ->> 'nome'), ''), nullif(trim(p_dados ->> 'descricao'), ''),
    nullif(trim(p_dados ->> 'proposta_origem_codigo'), ''), p_dados -> 'modelo',
    greatest(coalesce(nullif(p_dados ->> 'cpmv_unitario', '')::numeric, 0), 0),
    greatest(coalesce(nullif(p_dados ->> 'cpmv_total', '')::numeric, 0), 0),
    greatest(coalesce(nullif(p_dados ->> 'preco_calculado', '')::numeric, 0), 0),
    auth.uid(), auth.uid()
  ) returning * into v_registro;
  return to_jsonb(v_registro);
end;
$$;

-- O valor de referencia e sempre o da opcao principal. Alternativas sao
-- comparativas e nunca sao somadas ao cabecalho financeiro da proposta.
create or replace function propostas_mhs.recalcular_totais_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_base numeric(19,4);
  v_valor numeric(19,4);
  v_percentual numeric(19,6);
  v_fator numeric(19,10);
begin
  select coalesce(sum(x.base_cpmv), 0),
         coalesce(sum(case when x.modo_preco = 'MANUAL' and not x.tem_item_composto then x.preco_manual_total else x.preco_calculado end), 0)
  into v_base, v_valor
  from (
    select g.proposta_grupo_id, g.modo_preco, g.preco_manual_total,
           coalesce(sum(i.cpmv_total), 0) as base_cpmv,
           coalesce(sum(i.preco_venda_total), 0) as preco_calculado,
           coalesce(bool_or(i.modalidade = 'COMPOSTO'), false) as tem_item_composto
    from propostas_mhs.propostas_grupos g
    left join propostas_mhs.propostas_opcoes_comerciais o on o.proposta_opcao_id = g.proposta_opcao_id
    left join propostas_mhs.propostas_itens i on i.proposta_grupo_id = g.proposta_grupo_id
    where g.proposta_id = p_proposta_id
      and (o.ordem = 1 or not exists (
        select 1 from propostas_mhs.propostas_opcoes_comerciais op where op.proposta_id = p_proposta_id
      ))
    group by g.proposta_grupo_id, g.modo_preco, g.preco_manual_total
  ) x;
  v_fator := case when v_base > 0 then v_valor / v_base else 1 end;
  v_percentual := case when v_base > 0 then (v_fator - 1) * 100 else 0 end;
  update propostas_mhs.propostas
  set valor_cpmv_total = v_base, valor_base_calculo = v_base,
      percentual_total = greatest(v_percentual, 0), fator_venda = greatest(v_fator, 0.000001),
      valor_proposta = v_valor, atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;
  return jsonb_build_object('valor_base_calculo', v_base, 'percentual_total', greatest(v_percentual, 0), 'fator_venda', greatest(v_fator, 0.000001), 'valor_proposta', v_valor);
end;
$$;

-- Sincronizacao por diferenca: reordena sem colidir, vincula grupos e remove
-- somente opcoes que deixaram de existir no payload atual.
create or replace function api.sincronizar_opcoes_comerciais_proposta_mhs(
  p_proposta_id uuid, p_opcoes jsonb, p_grupo_opcoes jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_opcao jsonb; v_grupo jsonb; v_ordem integer := 0;
  v_chave text; v_opcao_id uuid;
begin
  perform api.exigir_editor();
  if jsonb_typeof(coalesce(p_opcoes, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_opcoes, '[]'::jsonb)) = 0 then
    raise exception 'A proposta precisa de ao menos uma opcao comercial.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_grupo_opcoes, '[]'::jsonb)) <> 'array' then
    raise exception 'grupo_opcoes deve ser uma lista.' using errcode = '22023';
  end if;
  perform 1 from propostas_mhs.propostas where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  update propostas_mhs.propostas_opcoes_comerciais
  set ordem = ordem + 1000000 where proposta_id = p_proposta_id;

  for v_opcao in select value from jsonb_array_elements(p_opcoes) loop
    v_ordem := v_ordem + 1;
    v_chave := nullif(trim(coalesce(v_opcao ->> 'id', v_opcao ->> 'chave_externa')), '');
    if v_chave is null then raise exception 'Cada opcao precisa de identificador estavel.' using errcode = '22023'; end if;
    insert into propostas_mhs.propostas_opcoes_comerciais
      (proposta_id, chave_externa, ordem, titulo, criado_por, atualizado_por)
    values
      (p_proposta_id, v_chave, v_ordem,
       coalesce(nullif(trim(v_opcao ->> 'title'), ''), case when v_ordem = 1 then '1. Dos produtos' else '1.' || (v_ordem - 1)::text || ' Dos produtos' end),
       auth.uid(), auth.uid())
    on conflict (proposta_id, chave_externa) do update
      set ordem = excluded.ordem, titulo = excluded.titulo,
          atualizado_por = auth.uid(), atualizado_em = now();
  end loop;

  for v_grupo in select value from jsonb_array_elements(p_grupo_opcoes) loop
    v_chave := nullif(trim(coalesce(v_grupo ->> 'commercialOptionId', v_grupo ->> 'chave_externa')), '');
    if v_chave is null then raise exception 'Todo grupo precisa de uma opcao comercial.' using errcode = '22023'; end if;
    select proposta_opcao_id into v_opcao_id
    from propostas_mhs.propostas_opcoes_comerciais
    where proposta_id = p_proposta_id and chave_externa = v_chave;
    if v_opcao_id is null then raise exception 'Opcao comercial % nao pertence a proposta.', v_chave using errcode = '22023'; end if;
    update propostas_mhs.propostas_grupos
    set proposta_opcao_id = v_opcao_id, atualizado_por = auth.uid(), atualizado_em = now()
    where proposta_id = p_proposta_id
      and ordem = coalesce(nullif(v_grupo ->> 'order', '')::integer, nullif(v_grupo ->> 'ordem', '')::integer);
    if not found then raise exception 'Grupo de ordem % nao encontrado.', coalesce(v_grupo ->> 'order', v_grupo ->> 'ordem') using errcode = 'P0002'; end if;
  end loop;

  if exists (select 1 from propostas_mhs.propostas_grupos where proposta_id = p_proposta_id and proposta_opcao_id is null) then
    raise exception 'Existem grupos sem opcao comercial.' using errcode = '23514';
  end if;

  delete from propostas_mhs.propostas_opcoes_comerciais o
  where o.proposta_id = p_proposta_id
    and not exists (
      select 1 from jsonb_array_elements(p_opcoes) e
      where nullif(trim(coalesce(e.value ->> 'id', e.value ->> 'chave_externa')), '') = o.chave_externa
    );
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.salvar_proposta_transacional_mhs(
  p_proposta_id uuid,
  p_dados jsonb,
  p_opcoes jsonb,
  p_grupo_opcoes jsonb,
  p_versao_esperada bigint default 0
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare v_versao bigint; v_resultado jsonb; v_totais jsonb; v_memoria jsonb;
begin
  perform api.exigir_editor();
  select versao_edicao into v_versao from propostas_mhs.propostas
  where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;
  if v_versao <> coalesce(p_versao_esperada, 0) then
    raise exception 'A proposta foi atualizada em outra operacao. Recarregue antes de salvar novamente.'
      using errcode = '40001', detail = format('versao_atual=%s; versao_recebida=%s', v_versao, p_versao_esperada);
  end if;

  perform api.atualizar_cabecalho_proposta_mhs(p_proposta_id, coalesce(p_dados -> 'cabecalho', '{}'::jsonb));
  perform api.salvar_proposta_completa_com_historico_mhs(p_proposta_id, p_dados);
  perform api.sincronizar_opcoes_comerciais_proposta_mhs(p_proposta_id, p_opcoes, p_grupo_opcoes);
  v_totais := propostas_mhs.recalcular_totais_proposta_mhs(p_proposta_id);
  -- O salvamento legado registra a memoria antes de os grupos receberem suas
  -- opcoes. Registra-se aqui a versao definitiva, ja reconciliada e recalculada.
  v_memoria := coalesce(p_dados -> 'memoria_calculo', '{}'::jsonb) || jsonb_build_object(
    'base_calculo', v_totais -> 'valor_base_calculo',
    'percentual_total', v_totais -> 'percentual_total',
    'fator_venda', v_totais -> 'fator_venda',
    'valor_resultado', v_totais -> 'valor_proposta'
  );
  perform api.registrar_memoria_calculo_proposta_mhs(p_proposta_id, v_memoria);
  update propostas_mhs.propostas
  set versao_edicao = versao_edicao + 1, atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id returning versao_edicao into v_versao;
  v_resultado := api.detalhar_proposta_mhs(p_proposta_id);
  return v_resultado || jsonb_build_object('versao_persistencia', v_versao);
end;
$$;

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
declare v_revisao propostas_mhs.propostas_revisoes%rowtype;
begin
  perform api.exigir_editor();
  perform 1 from propostas_mhs.propostas where proposta_id = p_proposta_id and numero_sequencial is not null for update;
  if not found then raise exception 'A proposta precisa receber numeracao antes da revisao.' using errcode = '55000'; end if;
  if nullif(trim(p_chave_idempotencia), '') is not null then
    select * into v_revisao from propostas_mhs.propostas_revisoes
    where proposta_id = p_proposta_id and chave_idempotencia = trim(p_chave_idempotencia);
    if found then
      if v_revisao.estado_emissao = 'FALHOU' then
        update propostas_mhs.propostas_revisoes
        set estado_emissao = 'PREPARANDO'
        where revisao_id = v_revisao.revisao_id returning * into v_revisao;
      end if;
      return to_jsonb(v_revisao);
    end if;
  end if;
  select * into v_revisao from propostas_mhs.criar_revisao_proposta(p_proposta_id, p_tipo, p_motivo);
  update propostas_mhs.propostas_revisoes
  set chave_idempotencia = nullif(trim(p_chave_idempotencia), ''), estado_emissao = 'PREPARANDO'
  where revisao_id = v_revisao.revisao_id returning * into v_revisao;
  return to_jsonb(v_revisao);
end;
$$;

create or replace function api.marcar_estado_revisao_mhs(p_proposta_id uuid, p_revisao_id uuid, p_estado text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare v_estado text := upper(trim(p_estado)); v_revisao propostas_mhs.propostas_revisoes%rowtype;
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
  ) then raise exception 'O PDF da revisao nao esta confirmado no bucket.' using errcode = '55000'; end if;
  update propostas_mhs.propostas_revisoes set estado_emissao = v_estado
  where proposta_id = p_proposta_id and revisao_id = p_revisao_id returning * into v_revisao;
  if not found then raise exception 'Revisao nao encontrada.' using errcode = 'P0002'; end if;
  return to_jsonb(v_revisao);
end;
$$;

-- Repetir uma tentativa de emissao sobrescreve o mesmo objeto no Storage e
-- reutiliza um unico registro de arquivo para a revisao.
create or replace function api.registrar_pdf_revisao_idempotente_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare v_existente jsonb;
begin
  perform api.exigir_editor();
  if upper(coalesce(p_dados ->> 'categoria', '')) <> 'PDF_GERADO' then
    raise exception 'Esta rotina aceita somente PDF_GERADO.' using errcode = '22023';
  end if;
  perform 1 from propostas_mhs.propostas_revisoes
  where proposta_id = nullif(p_dados ->> 'proposta_id', '')::uuid
    and revisao_id = nullif(p_dados ->> 'revisao_id', '')::uuid
  for update;
  if not found then raise exception 'Revisao nao encontrada.' using errcode = 'P0002'; end if;
  select to_jsonb(a) into v_existente
  from propostas_mhs.arquivos_proposta a
  where a.proposta_id = nullif(p_dados ->> 'proposta_id', '')::uuid
    and a.revisao_id = nullif(p_dados ->> 'revisao_id', '')::uuid
    and a.caminho_storage = p_dados ->> 'caminho_storage'
    and a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO'
  order by a.enviado_em desc limit 1;
  if v_existente is not null then return v_existente; end if;
  return api.registrar_arquivo_proposta_mhs(p_dados);
end;
$$;

revoke all on function api.salvar_conjunto_reutilizavel_mhs(jsonb) from public, anon;
revoke all on function api.salvar_proposta_transacional_mhs(uuid, jsonb, jsonb, jsonb, bigint) from public, anon;
revoke all on function api.criar_revisao_idempotente_mhs(uuid, text, text, text) from public, anon;
revoke all on function api.marcar_estado_revisao_mhs(uuid, uuid, text) from public, anon;
revoke all on function api.registrar_pdf_revisao_idempotente_mhs(jsonb) from public, anon;
grant execute on function api.salvar_conjunto_reutilizavel_mhs(jsonb) to authenticated;
grant execute on function api.salvar_proposta_transacional_mhs(uuid, jsonb, jsonb, jsonb, bigint) to authenticated;
grant execute on function api.criar_revisao_idempotente_mhs(uuid, text, text, text) to authenticated;
grant execute on function api.marcar_estado_revisao_mhs(uuid, uuid, text) to authenticated;
grant execute on function api.registrar_pdf_revisao_idempotente_mhs(jsonb) to authenticated;

notify pgrst, 'reload schema';
commit;
