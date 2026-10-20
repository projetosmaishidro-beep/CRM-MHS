-- ============================================================================
-- PROPOSTAS MHS - API SEGURA E STORAGE PRIVADO
--
-- Execute apos 20260927_0005_propostas_mhs_regras.sql.
-- As tabelas propostas_mhs continuam privadas. O navegador usa somente o schema
-- api, autenticado e autorizado pelas funcoes api.eh_membro/api.eh_editor.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. SUPERFICIE DE LEITURA PARA APLICACOES AUTENTICADAS
-- ---------------------------------------------------------------------------
create or replace view api.vw_propostas_mhs as
select
  p.proposta_id, p.codigo, p.ano, p.numero_sequencial, p.empresa_id,
  coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
  e.razao_social, e.nome_fantasia, e.cnpj, e.municipio, e.uf,
  o.local_obra_id, o.nome as local_obra,
  p.assunto, p.obra, p.descricao, p.complexidade, p.status, p.tipo_fornecimento,
  p.moeda, p.valor_cpmv_total, p.valor_base_calculo, p.percentual_total,
  p.fator_venda, p.valor_proposta, p.versao_atual, p.enviada_em, p.finalizada_em,
  p.validade_ate, p.criado_por, p.atualizado_por, p.criado_em, p.atualizado_em,
  u.email as responsavel_email
from propostas_mhs.propostas p
join cadastro.empresas e on e.empresa_id = p.empresa_id
left join propostas_mhs.locais_obra o on o.local_obra_id = p.local_obra_id
left join auth.users u on u.id = p.criado_por
where api.eh_membro();
comment on view api.vw_propostas_mhs is
'Lista autenticada de propostas com dados comerciais essenciais do cliente e da obra.';

create or replace view api.vw_clientes_propostas_mhs as
select
  e.empresa_id,
  coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
  e.razao_social, e.nome_fantasia, e.cnpj, e.contato_nome, e.telefone, e.whatsapp,
  e.email, e.logradouro, e.bairro, e.municipio, e.uf, e.cep,
  c.contato_preferencial_nome, c.contato_preferencial_cargo, c.contato_preferencial_canal,
  c.observacao_comercial,
  count(p.proposta_id) as total_propostas,
  max(p.criado_em) as ultima_proposta_em,
  max(p.atualizado_em) as ultima_atualizacao_proposta_em,
  coalesce(sum(p.valor_proposta) filter (where p.status in ('ENVIADA', 'APROVADA', 'FINALIZADA')), 0) as valor_em_propostas
from propostas_mhs.clientes c
join cadastro.empresas e on e.empresa_id = c.empresa_id
left join propostas_mhs.propostas p on p.empresa_id = c.empresa_id
where api.eh_membro()
group by
  e.empresa_id, e.razao_social, e.nome_fantasia, e.cnpj, e.contato_nome, e.telefone,
  e.whatsapp, e.email, e.logradouro, e.bairro, e.municipio, e.uf, e.cep,
  c.contato_preferencial_nome, c.contato_preferencial_cargo,
  c.contato_preferencial_canal, c.observacao_comercial;
comment on view api.vw_clientes_propostas_mhs is
'Clientes usados no modulo, com indicadores derivados de propostas sem duplicar o cadastro mestre.';

create or replace view api.vw_catalogo_propostas_mhs as
select
  i.item_catalogo_id, i.codigo, i.modalidade, i.nome, i.descricao_comercial,
  i.descricao_tecnica, i.ncm, i.unidade_padrao, i.ipi_padrao_percentual, i.ativo,
  c.cpmv_unitario as cpmv_atual,
  pv.preco_venda_unitario as preco_venda_atual,
  cv.composicao_versao_id as composicao_versao_vigente,
  cv.numero_versao as composicao_numero_versao,
  cv.cpmv_total as composicao_cpmv_total
from propostas_mhs.catalogo_itens i
left join lateral (
  select h.cpmv_unitario
  from propostas_mhs.historico_cpmv_produtos h
  where h.item_catalogo_id = i.item_catalogo_id
    and h.vigente_desde <= current_date
    and (h.vigente_ate is null or h.vigente_ate >= current_date)
  order by h.vigente_desde desc, h.criado_em desc
  limit 1
) c on true
left join lateral (
  select h.preco_venda_unitario
  from propostas_mhs.historico_precos_venda h
  where h.item_catalogo_id = i.item_catalogo_id
    and h.vigente_desde <= current_date
    and (h.vigente_ate is null or h.vigente_ate >= current_date)
  order by h.vigente_desde desc, h.criado_em desc
  limit 1
) pv on true
left join propostas_mhs.catalogo_composicoes cc on cc.item_catalogo_id = i.item_catalogo_id
left join lateral (
  select x.composicao_versao_id, x.numero_versao, x.cpmv_total
  from propostas_mhs.catalogo_composicoes_versoes x
  where x.composicao_id = cc.composicao_id and x.situacao = 'VIGENTE'
  order by x.numero_versao desc
  limit 1
) cv on true
where api.eh_membro();
comment on view api.vw_catalogo_propostas_mhs is
'Catalogo reutilizavel com CPMV, preco de venda e composicao vigente.';

create or replace view api.vw_templates_propostas_mhs as
select
  t.template_id, t.nome, t.tema, t.produto_referencia, t.descricao, t.situacao,
  t.versao_atual, t.criado_por, t.atualizado_por, t.criado_em, t.atualizado_em,
  tv.template_versao_id, tv.resumo_alteracao, tv.criado_em as versao_criada_em,
  count(a.arquivo_template_id) as total_arquivos
from propostas_mhs.templates t
left join propostas_mhs.templates_versoes tv
  on tv.template_id = t.template_id and tv.numero_versao = t.versao_atual
left join propostas_mhs.arquivos_template a on a.template_versao_id = tv.template_versao_id
where api.eh_membro()
group by t.template_id, tv.template_versao_id, tv.resumo_alteracao, tv.criado_em;
comment on view api.vw_templates_propostas_mhs is
'Templates versionados, organizados por tema e produto de referencia.';

create or replace view api.vw_historico_cpmv_mhs as
select
  h.historico_cpmv_id, h.item_catalogo_id, i.codigo, i.nome, i.modalidade,
  i.unidade_padrao, h.cpmv_unitario, h.moeda, h.vigente_desde, h.vigente_ate,
  h.fonte, h.documento_referencia, h.observacao, h.criado_por, h.criado_em,
  h.atualizado_por, h.atualizado_em
from propostas_mhs.historico_cpmv_produtos h
join propostas_mhs.catalogo_itens i on i.item_catalogo_id = h.item_catalogo_id
where api.eh_membro();
comment on view api.vw_historico_cpmv_mhs is
'Consulta autenticada do CPMV por produto, componente ou servico, incluindo vigencia e fonte.';

-- ---------------------------------------------------------------------------
-- 2. FUNCOES DE RECUPERACAO E CRIACAO CONTROLADA
-- ---------------------------------------------------------------------------
create or replace function api.detalhar_proposta_mhs(p_proposta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  return propostas_mhs.montar_snapshot_proposta(p_proposta_id);
end;
$$;

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
  v_numero integer;
  v_assunto text := nullif(trim(coalesce(p_dados ->> 'assunto', p_dados ->> 'subject', p_dados ->> 'title')), '');
  v_snapshot_cliente jsonb;
begin
  perform api.exigir_editor();

  if v_empresa_id is null then
    raise exception 'Informe a empresa_id do cliente para criar a proposta.' using errcode = '22023';
  end if;
  if v_assunto is null then
    raise exception 'Informe o assunto da proposta.' using errcode = '22023';
  end if;

  select r.relacionamento_id into v_relacionamento_id
  from crm.relacionamentos r
  where r.empresa_id = v_empresa_id and r.status = 'ATIVO';
  if v_relacionamento_id is null then
    raise exception 'Cliente nao encontrado ou arquivado no CRM.' using errcode = '23503';
  end if;

  if v_local_obra_id is not null and not exists (
    select 1 from propostas_mhs.locais_obra o
    where o.local_obra_id = v_local_obra_id and o.empresa_id = v_empresa_id and o.ativo
  ) then
    raise exception 'O local de obra informado nao pertence ao cliente.' using errcode = '23503';
  end if;

  select jsonb_build_object(
    'empresa_id', e.empresa_id, 'razao_social', e.razao_social, 'nome_fantasia', e.nome_fantasia,
    'cnpj', e.cnpj, 'contato_nome', e.contato_nome, 'contato_cargo', e.contato_cargo,
    'telefone', e.telefone, 'whatsapp', e.whatsapp, 'email', e.email,
    'logradouro', e.logradouro, 'bairro', e.bairro, 'municipio', e.municipio, 'uf', e.uf, 'cep', e.cep
  ) into v_snapshot_cliente
  from cadastro.empresas e where e.empresa_id = v_empresa_id;

  insert into propostas_mhs.clientes (empresa_id, relacionamento_id, criado_por, atualizado_por)
  values (v_empresa_id, v_relacionamento_id, auth.uid(), auth.uid())
  on conflict (empresa_id) do update set
    relacionamento_id = excluded.relacionamento_id,
    atualizado_por = auth.uid(),
    atualizado_em = now();

  v_numero := propostas_mhs.proximo_numero_proposta(v_ano);

  insert into propostas_mhs.propostas (
    ano, numero_sequencial, empresa_id, local_obra_id, assunto, obra, descricao,
    complexidade, status, tipo_fornecimento, validade_ate, dados_cliente_snapshot,
    dados_adicionais, criado_por, atualizado_por
  ) values (
    v_ano, v_numero, v_empresa_id, v_local_obra_id, v_assunto,
    nullif(trim(coalesce(p_dados ->> 'obra', p_dados ->> 'project')), ''),
    nullif(trim(coalesce(p_dados ->> 'descricao', p_dados ->> 'description')), ''),
    case upper(coalesce(p_dados ->> 'complexidade', 'MEDIA'))
      when 'BAIXA' then 'BAIXA' when 'ALTA' then 'ALTA' when 'ESPECIAL' then 'ESPECIAL' else 'MEDIA' end,
    'RASCUNHO',
    case upper(coalesce(p_dados ->> 'tipo_fornecimento', 'MISTO'))
      when 'PRODUTOS' then 'PRODUTOS' when 'SERVICOS' then 'SERVICOS'
      when 'COMPOSTOS' then 'COMPOSTOS' else 'MISTO' end,
    nullif(p_dados ->> 'validade_ate', '')::date,
    coalesce(v_snapshot_cliente, '{}'::jsonb),
    coalesce(p_dados -> 'dados_adicionais', '{}'::jsonb), auth.uid(), auth.uid()
  ) returning proposta_id into v_proposta_id;

  perform propostas_mhs.registrar_acao(
    'PROPOSTA', v_proposta_id, 'CRIADA', 'Proposta criada pelo modulo',
    jsonb_build_object('empresa_id', v_empresa_id)
  );

  return api.detalhar_proposta_mhs(v_proposta_id);
end;
$$;

create or replace function api.atualizar_cabecalho_proposta_mhs(p_proposta_id uuid, p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_status text;
begin
  perform api.exigir_editor();

  v_status := case upper(coalesce(p_dados ->> 'status', ''))
    when 'RASCUNHO' then 'RASCUNHO'
    when 'EM_EDICAO' then 'EM_EDICAO'
    when 'EM REVISAO' then 'EM_REVISAO'
    when 'EM_REVISAO' then 'EM_REVISAO'
    when 'ENVIADA' then 'ENVIADA'
    when 'APROVADA' then 'APROVADA'
    when 'RECUSADA' then 'RECUSADA'
    when 'CANCELADA' then 'CANCELADA'
    when 'FINALIZADA' then 'FINALIZADA'
    else null
  end;

  update propostas_mhs.propostas
  set assunto = coalesce(nullif(trim(coalesce(p_dados ->> 'assunto', p_dados ->> 'subject')), ''), assunto),
      obra = coalesce(nullif(trim(coalesce(p_dados ->> 'obra', p_dados ->> 'project')), ''), obra),
      descricao = coalesce(nullif(trim(coalesce(p_dados ->> 'descricao', p_dados ->> 'description')), ''), descricao),
      complexidade = case upper(coalesce(p_dados ->> 'complexidade', ''))
        when 'BAIXA' then 'BAIXA' when 'MEDIA' then 'MEDIA' when 'ALTA' then 'ALTA' when 'ESPECIAL' then 'ESPECIAL' else complexidade end,
      tipo_fornecimento = case upper(coalesce(p_dados ->> 'tipo_fornecimento', ''))
        when 'PRODUTOS' then 'PRODUTOS' when 'SERVICOS' then 'SERVICOS' when 'COMPOSTOS' then 'COMPOSTOS' when 'MISTO' then 'MISTO' else tipo_fornecimento end,
      status = coalesce(v_status, status),
      validade_ate = coalesce(nullif(p_dados ->> 'validade_ate', '')::date, validade_ate),
      valor_cpmv_total = coalesce(nullif(p_dados ->> 'valor_cpmv_total', '')::numeric, valor_cpmv_total),
      valor_base_calculo = coalesce(nullif(p_dados ->> 'valor_base_calculo', '')::numeric, valor_base_calculo),
      percentual_total = coalesce(nullif(p_dados ->> 'percentual_total', '')::numeric, percentual_total),
      fator_venda = coalesce(nullif(p_dados ->> 'fator_venda', '')::numeric, fator_venda),
      valor_proposta = coalesce(nullif(p_dados ->> 'valor_proposta', '')::numeric, valor_proposta),
      enviada_em = case when v_status = 'ENVIADA' then coalesce(enviada_em, now()) else enviada_em end,
      finalizada_em = case when v_status = 'FINALIZADA' then coalesce(finalizada_em, now()) else finalizada_em end,
      atualizado_por = auth.uid(), atualizado_em = now()
  where proposta_id = p_proposta_id;

  if not found then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  perform propostas_mhs.registrar_acao('PROPOSTA', p_proposta_id, 'ATUALIZADA', 'Cabecalho atualizado');
  return api.detalhar_proposta_mhs(p_proposta_id);
end;
$$;

create or replace function api.criar_revisao_proposta_mhs(
  p_proposta_id uuid,
  p_tipo text default 'REVISAO',
  p_motivo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_revisao propostas_mhs.propostas_revisoes%rowtype;
begin
  perform api.exigir_editor();
  select * into v_revisao
  from propostas_mhs.criar_revisao_proposta(p_proposta_id, p_tipo, p_motivo);
  return to_jsonb(v_revisao);
end;
$$;

create or replace function api.registrar_cpmv_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_id uuid;
begin
  perform api.exigir_editor();
  v_id := propostas_mhs.registrar_cpmv(
    nullif(p_dados ->> 'item_catalogo_id', '')::uuid,
    nullif(p_dados ->> 'cpmv_unitario', '')::numeric,
    coalesce(nullif(p_dados ->> 'vigente_desde', '')::date, current_date),
    p_dados ->> 'fonte', p_dados ->> 'documento_referencia', p_dados ->> 'observacao'
  );
  return (select to_jsonb(h) from propostas_mhs.historico_cpmv_produtos h where h.historico_cpmv_id = v_id);
end;
$$;

create or replace function api.registrar_preco_venda_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_id uuid;
begin
  perform api.exigir_editor();
  v_id := propostas_mhs.registrar_preco_venda(
    nullif(p_dados ->> 'item_catalogo_id', '')::uuid,
    nullif(p_dados ->> 'preco_venda_unitario', '')::numeric,
    coalesce(nullif(p_dados ->> 'vigente_desde', '')::date, current_date),
    p_dados ->> 'fonte', p_dados ->> 'observacao'
  );
  return (select to_jsonb(h) from propostas_mhs.historico_precos_venda h where h.historico_preco_id = v_id);
end;
$$;

create or replace function api.salvar_template_proposta_mhs(
  p_proposta_id uuid,
  p_nome text,
  p_tema text default null,
  p_produto_referencia text default null,
  p_resumo_alteracao text default null,
  p_template_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_template propostas_mhs.templates%rowtype;
  v_template_versao propostas_mhs.templates_versoes%rowtype;
  v_dados_modelo jsonb;
  v_cabecalho jsonb;
  v_numero integer;
begin
  perform api.exigir_editor();
  if nullif(trim(p_nome), '') is null then
    raise exception 'Informe um nome para o template.' using errcode = '22023';
  end if;

  v_dados_modelo := propostas_mhs.montar_snapshot_proposta(p_proposta_id);
  -- Dados de cliente e de obra sao removidos: templates nunca carregam dados comerciais de outra proposta.
  v_dados_modelo := v_dados_modelo - 'cliente_atual' - 'local_obra';
  v_cabecalho := coalesce(v_dados_modelo -> 'proposta', '{}'::jsonb)
    - 'proposta_id' - 'empresa_id' - 'local_obra_id' - 'visita_origem_id'
    - 'dados_cliente_snapshot' - 'codigo' - 'ano' - 'numero_sequencial'
    - 'criado_por' - 'atualizado_por' - 'criado_em' - 'atualizado_em';
  v_dados_modelo := jsonb_set(v_dados_modelo, '{proposta}', v_cabecalho, true);

  if p_template_id is null then
    insert into propostas_mhs.templates (
      nome, tema, produto_referencia, descricao, criado_por, atualizado_por
    ) values (
      trim(p_nome), nullif(trim(p_tema), ''), nullif(trim(p_produto_referencia), ''),
      nullif(trim(p_resumo_alteracao), ''), auth.uid(), auth.uid()
    ) returning * into v_template;
  else
    select * into v_template from propostas_mhs.templates
    where template_id = p_template_id for update;
    if not found then
      raise exception 'Template nao encontrado.' using errcode = 'P0002';
    end if;
    update propostas_mhs.templates
    set nome = trim(p_nome), tema = coalesce(nullif(trim(p_tema), ''), tema),
        produto_referencia = coalesce(nullif(trim(p_produto_referencia), ''), produto_referencia),
        descricao = coalesce(nullif(trim(p_resumo_alteracao), ''), descricao),
        atualizado_por = auth.uid(), atualizado_em = now()
    where template_id = p_template_id
    returning * into v_template;
  end if;

  v_numero := v_template.versao_atual + 1;
  insert into propostas_mhs.templates_versoes (
    template_id, numero_versao, resumo_alteracao, dados_modelo, criado_por
  ) values (
    v_template.template_id, v_numero, nullif(trim(p_resumo_alteracao), ''),
    v_dados_modelo, auth.uid()
  ) returning * into v_template_versao;

  update propostas_mhs.templates
  set versao_atual = v_numero, situacao = 'ATIVO', atualizado_por = auth.uid(), atualizado_em = now()
  where template_id = v_template.template_id;

  perform propostas_mhs.registrar_acao(
    'TEMPLATE', v_template.template_id, 'REVISADA',
    'Template salvo na versao ' || v_numero::text,
    jsonb_build_object('template_versao_id', v_template_versao.template_versao_id, 'proposta_origem_id', p_proposta_id)
  );

  return jsonb_build_object(
    'template_id', v_template.template_id,
    'template_versao_id', v_template_versao.template_versao_id,
    'numero_versao', v_numero,
    'dados_modelo', v_dados_modelo
  );
end;
$$;

create or replace function api.obter_template_proposta_mhs(
  p_template_id uuid,
  p_numero_versao integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_dados jsonb;
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;

  select tv.dados_modelo into v_dados
  from propostas_mhs.templates t
  join propostas_mhs.templates_versoes tv on tv.template_id = t.template_id
  where t.template_id = p_template_id
    and tv.numero_versao = coalesce(p_numero_versao, t.versao_atual);

  if v_dados is null then
    raise exception 'Template ou versao nao encontrada.' using errcode = 'P0002';
  end if;
  return v_dados;
end;
$$;

create or replace function api.registrar_arquivo_proposta_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_proposta_id uuid := nullif(p_dados ->> 'proposta_id', '')::uuid;
  v_revisao_id uuid := nullif(p_dados ->> 'revisao_id', '')::uuid;
  v_empresa_id uuid;
  v_numero_revisao integer;
  v_prefixo text;
  v_arquivo_id uuid;
  v_categoria text := upper(coalesce(p_dados ->> 'categoria', 'OUTRO'));
begin
  perform api.exigir_editor();
  select empresa_id into v_empresa_id from propostas_mhs.propostas where proposta_id = v_proposta_id;
  if v_empresa_id is null then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;

  v_prefixo := 'clientes/' || v_empresa_id::text || '/propostas/' || v_proposta_id::text || '/';
  if v_revisao_id is not null then
    select numero_revisao into v_numero_revisao from propostas_mhs.propostas_revisoes
    where revisao_id = v_revisao_id and proposta_id = v_proposta_id;
    if v_numero_revisao is null then
      raise exception 'A revisao nao pertence a proposta informada.' using errcode = '23503';
    end if;
    v_prefixo := v_prefixo || 'revisoes/R' || v_numero_revisao::text || '/';
  end if;

  if coalesce(p_dados ->> 'caminho_storage', '') not like v_prefixo || '%' then
    raise exception 'O caminho do arquivo deve iniciar com %', v_prefixo using errcode = '22023';
  end if;
  if v_categoria = 'PDF_GERADO' and (v_revisao_id is null or (p_dados ->> 'caminho_storage') not like v_prefixo || 'pdf/%') then
    raise exception 'PDF gerado deve pertencer a uma revisao e ficar na pasta pdf.' using errcode = '22023';
  end if;

  insert into propostas_mhs.arquivos_proposta (
    proposta_id, revisao_id, caminho_storage, categoria, nome_original, tipo_mime,
    tamanho_bytes, checksum_sha256, observacao, enviado_por
  ) values (
    v_proposta_id, v_revisao_id, p_dados ->> 'caminho_storage', v_categoria,
    nullif(trim(p_dados ->> 'nome_original'), ''), nullif(trim(p_dados ->> 'tipo_mime'), ''),
    nullif(p_dados ->> 'tamanho_bytes', '')::bigint, nullif(trim(p_dados ->> 'checksum_sha256'), ''),
    nullif(trim(p_dados ->> 'observacao'), ''), auth.uid()
  ) returning arquivo_id into v_arquivo_id;

  perform propostas_mhs.registrar_acao('ARQUIVO_PROPOSTA', v_arquivo_id, 'CRIADA', 'Arquivo registrado');
  return (select to_jsonb(a) from propostas_mhs.arquivos_proposta a where a.arquivo_id = v_arquivo_id);
end;
$$;

create or replace function api.registrar_arquivo_template_mhs(p_dados jsonb)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs
as $$
declare
  v_template_versao_id uuid := nullif(p_dados ->> 'template_versao_id', '')::uuid;
  v_template_id uuid;
  v_numero integer;
  v_prefixo text;
  v_id uuid;
begin
  perform api.exigir_editor();
  select template_id, numero_versao into v_template_id, v_numero
  from propostas_mhs.templates_versoes where template_versao_id = v_template_versao_id;
  if v_template_id is null then
    raise exception 'Versao de template nao encontrada.' using errcode = 'P0002';
  end if;

  v_prefixo := 'templates/' || v_template_id::text || '/versoes/V' || v_numero::text || '/';
  if coalesce(p_dados ->> 'caminho_storage', '') not like v_prefixo || '%' then
    raise exception 'O caminho do arquivo deve iniciar com %', v_prefixo using errcode = '22023';
  end if;

  insert into propostas_mhs.arquivos_template (
    template_versao_id, caminho_storage, categoria, nome_original, tipo_mime,
    tamanho_bytes, checksum_sha256, enviado_por
  ) values (
    v_template_versao_id, p_dados ->> 'caminho_storage',
    upper(coalesce(p_dados ->> 'categoria', 'OUTRO')),
    nullif(trim(p_dados ->> 'nome_original'), ''), nullif(trim(p_dados ->> 'tipo_mime'), ''),
    nullif(p_dados ->> 'tamanho_bytes', '')::bigint,
    nullif(trim(p_dados ->> 'checksum_sha256'), ''), auth.uid()
  ) returning arquivo_template_id into v_id;

  perform propostas_mhs.registrar_acao('ARQUIVO_TEMPLATE', v_id, 'CRIADA', 'Arquivo de template registrado');
  return (select to_jsonb(a) from propostas_mhs.arquivos_template a where a.arquivo_template_id = v_id);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. RLS, GRANTS E BUCKET PRIVADO
-- ---------------------------------------------------------------------------
revoke all on schema propostas_mhs from public, anon, authenticated;
revoke all on all tables in schema propostas_mhs from public, anon, authenticated;
revoke all on all sequences in schema propostas_mhs from public, anon, authenticated;

alter table propostas_mhs.clientes enable row level security;
alter table propostas_mhs.locais_obra enable row level security;
alter table propostas_mhs.catalogo_itens enable row level security;
alter table propostas_mhs.catalogo_composicoes enable row level security;
alter table propostas_mhs.catalogo_composicoes_versoes enable row level security;
alter table propostas_mhs.catalogo_composicao_componentes enable row level security;
alter table propostas_mhs.historico_cpmv_produtos enable row level security;
alter table propostas_mhs.historico_precos_venda enable row level security;
alter table propostas_mhs.blocos_inteligentes enable row level security;
alter table propostas_mhs.blocos_inteligentes_versoes enable row level security;
alter table propostas_mhs.templates enable row level security;
alter table propostas_mhs.templates_versoes enable row level security;
alter table propostas_mhs.numeracao_anual enable row level security;
alter table propostas_mhs.propostas enable row level security;
alter table propostas_mhs.propostas_itens enable row level security;
alter table propostas_mhs.propostas_itens_composicao enable row level security;
alter table propostas_mhs.propostas_condicoes enable row level security;
alter table propostas_mhs.propostas_pagamentos enable row level security;
alter table propostas_mhs.propostas_escopo enable row level security;
alter table propostas_mhs.propostas_referencias enable row level security;
alter table propostas_mhs.memorias_calculo enable row level security;
alter table propostas_mhs.memorias_calculo_linhas enable row level security;
alter table propostas_mhs.propostas_blocos enable row level security;
alter table propostas_mhs.propostas_revisoes enable row level security;
alter table propostas_mhs.arquivos_proposta enable row level security;
alter table propostas_mhs.arquivos_template enable row level security;
alter table propostas_mhs.historico_acoes enable row level security;

revoke all on all functions in schema propostas_mhs from public, anon, authenticated;
revoke all on all functions in schema api from public, anon;
grant usage on schema api to authenticated;
grant select on api.vw_propostas_mhs, api.vw_clientes_propostas_mhs,
  api.vw_catalogo_propostas_mhs, api.vw_templates_propostas_mhs,
  api.vw_historico_cpmv_mhs to authenticated;
grant execute on function
  api.detalhar_proposta_mhs(uuid),
  api.criar_proposta_mhs(jsonb),
  api.atualizar_cabecalho_proposta_mhs(uuid, jsonb),
  api.criar_revisao_proposta_mhs(uuid, text, text),
  api.registrar_cpmv_mhs(jsonb),
  api.registrar_preco_venda_mhs(jsonb),
  api.salvar_template_proposta_mhs(uuid, text, text, text, text, uuid),
  api.obter_template_proposta_mhs(uuid, integer),
  api.registrar_arquivo_proposta_mhs(jsonb),
  api.registrar_arquivo_template_mhs(jsonb)
to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'propostas-mhs', 'propostas-mhs', false, 52428800,
  array[
    'application/pdf', 'image/jpeg', 'image/png', 'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'application/vnd.ms-excel', 'text/plain'
  ]
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Rotas aceitas:
-- clientes/{empresa_uuid}/propostas/{proposta_uuid}/revisoes/R{numero}/{pdf|anexos|imagens|tecnicos}/{arquivo}
-- templates/{template_uuid}/versoes/V{numero}/{anexos|imagens|tecnicos}/{arquivo}
drop policy if exists propostas_mhs_leitura_membros on storage.objects;
create policy propostas_mhs_leitura_membros on storage.objects for select to authenticated
using (bucket_id = 'propostas-mhs' and api.eh_membro());
drop policy if exists propostas_mhs_envio_editores on storage.objects;
create policy propostas_mhs_envio_editores on storage.objects for insert to authenticated
with check (
  bucket_id = 'propostas-mhs' and api.eh_editor() and name ~
  '^(clientes/[0-9a-fA-F-]+/propostas/[0-9a-fA-F-]+/revisoes/R[0-9]+/(pdf|anexos|imagens|tecnicos)/[^/]+|templates/[0-9a-fA-F-]+/versoes/V[0-9]+/(anexos|imagens|tecnicos)/[^/]+)$'
);
drop policy if exists propostas_mhs_atualizacao_editores on storage.objects;
create policy propostas_mhs_atualizacao_editores on storage.objects for update to authenticated
using (bucket_id = 'propostas-mhs' and api.eh_editor())
with check (
  bucket_id = 'propostas-mhs' and api.eh_editor() and name ~
  '^(clientes/[0-9a-fA-F-]+/propostas/[0-9a-fA-F-]+/revisoes/R[0-9]+/(pdf|anexos|imagens|tecnicos)/[^/]+|templates/[0-9a-fA-F-]+/versoes/V[0-9]+/(anexos|imagens|tecnicos)/[^/]+)$'
);
drop policy if exists propostas_mhs_exclusao_admin on storage.objects;
create policy propostas_mhs_exclusao_admin on storage.objects for delete to authenticated
using (bucket_id = 'propostas-mhs' and api.eh_admin());

notify pgrst, 'reload schema';
commit;
