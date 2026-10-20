-- ============================================================================
-- PROPOSTAS MHS - GALERIA DE PDFs AGRUPADA POR PROPOSTA E REVISAO
-- Execute depois de 20260927_0025_galeria_pdfs_propostas_mhs.sql.
-- A consulta nova preserva a RPC anterior e usa paginação por cursor.
-- ============================================================================

begin;

create or replace function api.listar_galeria_pdfs_propostas_mhs(
  p_busca text default null,
  p_incluir_revisoes boolean default true,
  p_ordem text default 'RECENTES',
  p_limite integer default 13,
  p_antes_de timestamptz default null,
  p_antes_arquivo_id uuid default null,
  p_antes_codigo text default null,
  p_antes_numero_revisao integer default null
)
returns table (
  arquivo_id uuid,
  proposta_id uuid,
  revisao_id uuid,
  codigo text,
  cliente text,
  assunto text,
  numero_revisao integer,
  tipo_revisao text,
  valor_proposta numeric,
  bucket_id text,
  caminho_storage text,
  nome_original text,
  tamanho_bytes bigint,
  enviado_em timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, cadastro, storage
as $$
declare
  v_busca text := nullif(lower(trim(p_busca)), '');
  v_limite integer := greatest(1, least(coalesce(p_limite, 13), 100));
  v_ordem text := upper(coalesce(nullif(trim(p_ordem), ''), 'RECENTES'));
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  if v_ordem not in ('RECENTES', 'PROPOSTA_DESC') then
    raise exception 'Ordenacao invalida para a galeria de PDFs.' using errcode = '22023';
  end if;
  if v_ordem = 'RECENTES' and ((p_antes_de is null) <> (p_antes_arquivo_id is null)) then
    raise exception 'O cursor recente deve informar data e arquivo juntos.' using errcode = '22023';
  end if;
  if v_ordem = 'PROPOSTA_DESC' and (
    (p_antes_codigo is null) <> (p_antes_numero_revisao is null)
    or (p_antes_codigo is null) <> (p_antes_arquivo_id is null)
  ) then
    raise exception 'O cursor por proposta deve informar codigo, revisao e arquivo juntos.' using errcode = '22023';
  end if;

  if v_ordem = 'RECENTES' then
    return query
    with arquivos as (
      select
        a.arquivo_id, p.proposta_id, r.revisao_id, p.codigo,
        coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
        p.assunto, r.numero_revisao, r.tipo as tipo_revisao, r.valor_proposta,
        a.bucket_id, a.caminho_storage, a.nome_original, a.tamanho_bytes, a.enviado_em,
        row_number() over (
          partition by p.proposta_id
          order by r.numero_revisao desc, a.enviado_em desc, a.arquivo_id desc
        ) as ordem_revisao
      from propostas_mhs.arquivos_proposta a
      join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
      join propostas_mhs.propostas_revisoes r
        on r.revisao_id = a.revisao_id and r.proposta_id = a.proposta_id
      join cadastro.empresas e on e.empresa_id = p.empresa_id
      join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
      where a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO' and a.tamanho_bytes > 0
        and (
          v_busca is null
          or lower(p.codigo) like '%' || v_busca || '%'
          or lower(coalesce(e.nome_fantasia, e.razao_social, e.cnpj, '')) like '%' || v_busca || '%'
          or lower(coalesce(p.assunto, '')) like '%' || v_busca || '%'
        )
    )
    select f.arquivo_id, f.proposta_id, f.revisao_id, f.codigo, f.cliente, f.assunto, f.numero_revisao,
      f.tipo_revisao, f.valor_proposta, f.bucket_id, f.caminho_storage, f.nome_original, f.tamanho_bytes, f.enviado_em
    from arquivos f
    where (p_incluir_revisoes or f.ordem_revisao = 1)
      and (p_antes_de is null or (f.enviado_em, f.arquivo_id) < (p_antes_de, p_antes_arquivo_id))
    order by f.enviado_em desc, f.arquivo_id desc
    limit v_limite;
  else
    return query
    with arquivos as (
      select
        a.arquivo_id, p.proposta_id, r.revisao_id, p.codigo,
        coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
        p.assunto, r.numero_revisao, r.tipo as tipo_revisao, r.valor_proposta,
        a.bucket_id, a.caminho_storage, a.nome_original, a.tamanho_bytes, a.enviado_em,
        row_number() over (
          partition by p.proposta_id
          order by r.numero_revisao desc, a.enviado_em desc, a.arquivo_id desc
        ) as ordem_revisao
      from propostas_mhs.arquivos_proposta a
      join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
      join propostas_mhs.propostas_revisoes r
        on r.revisao_id = a.revisao_id and r.proposta_id = a.proposta_id
      join cadastro.empresas e on e.empresa_id = p.empresa_id
      join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
      where a.categoria = 'PDF_GERADO' and a.estado = 'ATIVO' and a.tamanho_bytes > 0
        and (
          v_busca is null
          or lower(p.codigo) like '%' || v_busca || '%'
          or lower(coalesce(e.nome_fantasia, e.razao_social, e.cnpj, '')) like '%' || v_busca || '%'
          or lower(coalesce(p.assunto, '')) like '%' || v_busca || '%'
        )
    )
    select f.arquivo_id, f.proposta_id, f.revisao_id, f.codigo, f.cliente, f.assunto, f.numero_revisao,
      f.tipo_revisao, f.valor_proposta, f.bucket_id, f.caminho_storage, f.nome_original, f.tamanho_bytes, f.enviado_em
    from arquivos f
    where (p_incluir_revisoes or f.ordem_revisao = 1)
      and (
        p_antes_codigo is null
        or (f.codigo, f.numero_revisao, f.arquivo_id) < (p_antes_codigo, p_antes_numero_revisao, p_antes_arquivo_id)
      )
    order by f.codigo desc, f.numero_revisao desc, f.arquivo_id desc
    limit v_limite;
  end if;
end;
$$;

revoke all on function api.listar_galeria_pdfs_propostas_mhs(text, boolean, text, integer, timestamptz, uuid, text, integer) from public, anon;
grant execute on function api.listar_galeria_pdfs_propostas_mhs(text, boolean, text, integer, timestamptz, uuid, text, integer) to authenticated;

notify pgrst, 'reload schema';
commit;
