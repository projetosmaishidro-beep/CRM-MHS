-- ============================================================================
-- PROPOSTAS MHS - GALERIA PRIVADA DE PDFs EMITIDOS
-- Execute depois de 20260927_0024_templates_mhs_edicao_direta.sql.
-- Apenas expõe metadados de PDFs ativos cujo objeto existe no Storage.
-- ============================================================================

begin;

-- A paginação usa cursor composto, evitando o custo e a instabilidade de OFFSET
-- quando novos PDFs são emitidos enquanto a galeria está sendo consultada.
create index if not exists arquivos_proposta_galeria_pdf_cursor_idx
  on propostas_mhs.arquivos_proposta (enviado_em desc, arquivo_id desc)
  where categoria = 'PDF_GERADO' and estado = 'ATIVO';

create or replace function api.listar_pdfs_propostas_mhs(
  p_busca text default null,
  p_limite integer default 12,
  p_antes_de timestamptz default null,
  p_antes_arquivo_id uuid default null
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
  v_limite integer := greatest(1, least(coalesce(p_limite, 12), 100));
begin
  if not api.eh_membro() then
    raise exception 'Seu usuario nao possui acesso ao modulo de propostas.' using errcode = '42501';
  end if;
  if (p_antes_de is null) <> (p_antes_arquivo_id is null) then
    raise exception 'O cursor da galeria deve informar data e arquivo juntos.' using errcode = '22023';
  end if;

  return query
  select
    a.arquivo_id,
    p.proposta_id,
    r.revisao_id,
    p.codigo,
    coalesce(e.nome_fantasia, e.razao_social, e.cnpj, 'Cliente sem nome') as cliente,
    p.assunto,
    r.numero_revisao,
    r.tipo as tipo_revisao,
    r.valor_proposta,
    a.bucket_id,
    a.caminho_storage,
    a.nome_original,
    a.tamanho_bytes,
    a.enviado_em
  from propostas_mhs.arquivos_proposta a
  join propostas_mhs.propostas p on p.proposta_id = a.proposta_id
  join propostas_mhs.propostas_revisoes r
    on r.revisao_id = a.revisao_id and r.proposta_id = a.proposta_id
  join cadastro.empresas e on e.empresa_id = p.empresa_id
  join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
  where a.categoria = 'PDF_GERADO'
    and a.estado = 'ATIVO'
    and a.tamanho_bytes > 0
    and (p_antes_de is null or (a.enviado_em, a.arquivo_id) < (p_antes_de, p_antes_arquivo_id))
    and (
      v_busca is null
      or lower(p.codigo) like '%' || v_busca || '%'
      or lower(coalesce(e.nome_fantasia, e.razao_social, e.cnpj, '')) like '%' || v_busca || '%'
      or lower(coalesce(p.assunto, '')) like '%' || v_busca || '%'
    )
  order by a.enviado_em desc, a.arquivo_id desc
  limit v_limite;
end;
$$;

revoke all on function api.listar_pdfs_propostas_mhs(text, integer, timestamptz, uuid) from public, anon;
grant execute on function api.listar_pdfs_propostas_mhs(text, integer, timestamptz, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;
