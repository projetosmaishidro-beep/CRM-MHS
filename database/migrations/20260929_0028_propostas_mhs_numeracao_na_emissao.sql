-- ============================================================================
-- PROPOSTAS MHS - NUMERACAO OFICIAL SOMENTE NA EMISSAO
-- Execute apos 20260927_0027_controles_operacionais_propostas_mhs.sql.
-- Rascunhos possuem UUID e codigo nulo; a sequencia anual e reservada em
-- transacao imediatamente antes da primeira emissao/revisao com PDF.
-- ============================================================================

begin;

alter table propostas_mhs.propostas
  alter column numero_sequencial drop not null;

comment on column propostas_mhs.propostas.numero_sequencial is
  'Numero comercial anual. Nulo enquanto a proposta for rascunho; reservado transacionalmente na emissao.';

create or replace function api.criar_proposta_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, cadastro, crm, propostas_mhs
as $$
declare
  v_empresa_id uuid := nullif(coalesce(p_dados ->> 'empresa_id', p_dados ->> 'clientId'), '')::uuid;
  v_local_obra_id uuid := nullif(p_dados ->> 'local_obra_id', '')::uuid;
  v_relacionamento_id uuid;
  v_proposta_id uuid;
  v_ano integer := coalesce(nullif(p_dados ->> 'ano', '')::integer, extract(year from current_date)::integer);
  v_assunto text := nullif(trim(coalesce(p_dados ->> 'assunto', p_dados ->> 'subject', p_dados ->> 'title')), '');
  v_snapshot_cliente jsonb;
begin
  perform api.exigir_editor();
  if v_empresa_id is null then raise exception 'Informe a empresa_id do cliente para criar a proposta.' using errcode = '22023'; end if;
  if v_assunto is null then raise exception 'Informe o assunto da proposta.' using errcode = '22023'; end if;

  select r.relacionamento_id into v_relacionamento_id
  from crm.relacionamentos r where r.empresa_id = v_empresa_id and r.status = 'ATIVO';
  if v_relacionamento_id is null then raise exception 'Cliente nao encontrado ou arquivado no CRM.' using errcode = '23503'; end if;
  if v_local_obra_id is not null and not exists (
    select 1 from propostas_mhs.locais_obra o where o.local_obra_id = v_local_obra_id and o.empresa_id = v_empresa_id and o.ativo
  ) then raise exception 'O local de obra informado nao pertence ao cliente.' using errcode = '23503'; end if;

  select jsonb_build_object(
    'empresa_id', e.empresa_id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia,
    'cnpj', e.cnpj, 'contato_nome', e.contato_nome, 'contato_cargo', e.contato_cargo,
    'telefone', e.telefone, 'whatsapp', e.whatsapp, 'email', e.email,
    'logradouro', e.logradouro, 'bairro', e.bairro, 'municipio', e.municipio, 'uf', e.uf, 'cep', e.cep
  ) into v_snapshot_cliente from cadastro.empresas e where e.empresa_id = v_empresa_id;

  insert into propostas_mhs.clientes (empresa_id, relacionamento_id, criado_por, atualizado_por)
  values (v_empresa_id, v_relacionamento_id, auth.uid(), auth.uid())
  on conflict (empresa_id) do update set relacionamento_id = excluded.relacionamento_id, atualizado_por = auth.uid(), atualizado_em = now();

  insert into propostas_mhs.propostas (
    ano, empresa_id, local_obra_id, assunto, obra, descricao, complexidade, status,
    tipo_fornecimento, validade_ate, dados_cliente_snapshot, dados_adicionais, criado_por, atualizado_por
  ) values (
    v_ano, v_empresa_id, v_local_obra_id, v_assunto,
    nullif(trim(coalesce(p_dados ->> 'obra', p_dados ->> 'project')), ''),
    nullif(trim(coalesce(p_dados ->> 'descricao', p_dados ->> 'description')), ''),
    case upper(coalesce(p_dados ->> 'complexidade', 'MEDIA')) when 'BAIXA' then 'BAIXA' when 'ALTA' then 'ALTA' when 'ESPECIAL' then 'ESPECIAL' else 'MEDIA' end,
    'RASCUNHO',
    case upper(coalesce(p_dados ->> 'tipo_fornecimento', 'MISTO')) when 'PRODUTOS' then 'PRODUTOS' when 'SERVICOS' then 'SERVICOS' when 'COMPOSTOS' then 'COMPOSTOS' else 'MISTO' end,
    nullif(p_dados ->> 'validade_ate', '')::date, coalesce(v_snapshot_cliente, '{}'::jsonb),
    coalesce(p_dados -> 'dados_adicionais', '{}'::jsonb), auth.uid(), auth.uid()
  ) returning proposta_id into v_proposta_id;

  perform propostas_mhs.registrar_acao('PROPOSTA', v_proposta_id, 'RASCUNHO_CRIADO', 'Rascunho criado sem numeracao comercial', jsonb_build_object('empresa_id', v_empresa_id));
  return api.detalhar_proposta_mhs(v_proposta_id);
end;
$$;

create or replace function api.reservar_numeracao_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_ano integer;
  v_numero integer;
begin
  perform api.exigir_editor();
  select ano, numero_sequencial into v_ano, v_numero
  from propostas_mhs.propostas where proposta_id = p_proposta_id for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  if v_numero is null then
    v_ano := extract(year from current_date)::integer;
    v_numero := propostas_mhs.proximo_numero_proposta(v_ano);
    update propostas_mhs.propostas
    set ano = v_ano, numero_sequencial = v_numero, atualizado_por = auth.uid(), atualizado_em = now()
    where proposta_id = p_proposta_id;
    perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'NUMERADA', 'Numeracao comercial reservada na emissao', jsonb_build_object('ano', v_ano, 'numero_sequencial', v_numero));
  end if;
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.criar_revisao_proposta_mhs(p_proposta_id uuid, p_tipo text default 'REVISAO', p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare v_revisao propostas_mhs.propostas_revisoes%rowtype;
begin
  perform api.exigir_editor();
  if not exists (select 1 from propostas_mhs.propostas where proposta_id = p_proposta_id and numero_sequencial is not null) then
    raise exception 'A proposta precisa receber numeracao oficial antes de criar uma revisao.' using errcode = '55000';
  end if;
  select * into v_revisao from propostas_mhs.criar_revisao_proposta(p_proposta_id, p_tipo, p_motivo);
  return to_jsonb(v_revisao);
end;
$$;

revoke all on function api.reservar_numeracao_proposta_mhs(uuid) from public, anon;
grant execute on function api.reservar_numeracao_proposta_mhs(uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
