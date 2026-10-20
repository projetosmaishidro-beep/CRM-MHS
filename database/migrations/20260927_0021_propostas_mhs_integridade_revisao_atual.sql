-- ============================================================================
-- PROPOSTAS MHS - INTEGRIDADE DA REVISAO ATUAL E DO PDF
-- Execute depois de 20260927_0020_propostas_mhs_arquivos_rascunho.sql.
-- ============================================================================

begin;

-- A protecao e feita na propria tabela para cobrir toda RPC presente ou futura.
-- Uma revisao anterior com PDF nao autoriza finalizar uma revisao nova sem PDF.
create or replace function propostas_mhs.validar_pdf_revisao_atual()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs, storage
as $$
begin
  if new.status = 'FINALIZADA' and old.status is distinct from 'FINALIZADA' then
    if not exists (
      select 1
      from propostas_mhs.propostas_revisoes r
      join propostas_mhs.arquivos_proposta a
        on a.proposta_id = r.proposta_id and a.revisao_id = r.revisao_id
      join storage.objects o
        on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
      where r.proposta_id = new.proposta_id
        and r.numero_revisao = new.versao_atual
        and a.categoria = 'PDF_GERADO'
        and a.estado = 'ATIVO'
        and a.tamanho_bytes > 0
    ) then
      raise exception 'A revisao atual (%) precisa ter PDF confirmado no bucket antes da finalizacao.', new.versao_atual using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists propostas_validar_pdf_revisao_atual on propostas_mhs.propostas;
create trigger propostas_validar_pdf_revisao_atual
before update of status on propostas_mhs.propostas
for each row execute function propostas_mhs.validar_pdf_revisao_atual();

create or replace function api.confirmar_revisao_proposta_mhs(
  p_proposta_id uuid,
  p_revisao_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, api, propostas_mhs, storage
as $$
declare
  v_versao_atual integer;
  v_revisao propostas_mhs.propostas_revisoes%rowtype;
begin
  perform api.exigir_editor();
  select versao_atual into v_versao_atual
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id
  for update;
  if not found then raise exception 'Proposta nao encontrada.' using errcode = 'P0002'; end if;

  select * into v_revisao
  from propostas_mhs.propostas_revisoes
  where revisao_id = p_revisao_id
    and proposta_id = p_proposta_id
    and numero_revisao = v_versao_atual;
  if not found then raise exception 'A revisao informada nao e a revisao atual da proposta.' using errcode = '55000'; end if;

  if not exists (
    select 1
    from propostas_mhs.arquivos_proposta a
    join storage.objects o on o.bucket_id = a.bucket_id and o.name = a.caminho_storage
    where a.proposta_id = p_proposta_id
      and a.revisao_id = p_revisao_id
      and a.categoria = 'PDF_GERADO'
      and a.estado = 'ATIVO'
      and a.tamanho_bytes > 0
  ) then
    raise exception 'A revisao atual nao possui PDF confirmado no bucket.' using errcode = '55000';
  end if;

  return jsonb_build_object('revisao_id', v_revisao.revisao_id, 'numero_revisao', v_revisao.numero_revisao, 'confirmada', true);
end;
$$;

revoke all on function propostas_mhs.validar_pdf_revisao_atual() from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
