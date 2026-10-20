-- ============================================================================
-- ESTABILIZACAO MHS - HISTORICO EM RASCUNHOS SEM NUMERACAO
-- Execute apos 20260929_0028_propostas_mhs_numeracao_na_emissao.sql.
-- ============================================================================

begin;

create or replace function propostas_mhs.sincronizar_historico_catalogo_da_proposta(p_proposta_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, propostas_mhs
as $$
declare
  v_item record;
  v_proposta_codigo text;
  v_cpmv_atual propostas_mhs.historico_cpmv_produtos%rowtype;
  v_preco_atual propostas_mhs.historico_precos_venda%rowtype;
  v_fonte text;
begin
  -- Codigo nulo identifica um rascunho valido, nao uma proposta inexistente.
  select coalesce(codigo, 'RASCUNHO-' || left(proposta_id::text, 8))
    into v_proposta_codigo
  from propostas_mhs.propostas
  where proposta_id = p_proposta_id;
  if v_proposta_codigo is null then
    raise exception 'Proposta nao encontrada.' using errcode = 'P0002';
  end if;
  v_fonte := 'Proposta ' || v_proposta_codigo;

  for v_item in
    select item_catalogo_id,
      min(cpmv_unitario) filter (where cpmv_unitario is not null) as cpmv_unitario,
      min(preco_venda_unitario) filter (where preco_venda_unitario is not null) as preco_venda_unitario,
      count(distinct cpmv_unitario) filter (where cpmv_unitario is not null) as cpmv_distintos,
      count(distinct preco_venda_unitario) filter (where preco_venda_unitario is not null) as preco_distintos
    from propostas_mhs.propostas_itens
    where proposta_id = p_proposta_id and item_catalogo_id is not null and ativo
    group by item_catalogo_id
  loop
    if v_item.cpmv_distintos = 1 then
      select * into v_cpmv_atual
      from propostas_mhs.historico_cpmv_produtos
      where item_catalogo_id = v_item.item_catalogo_id and vigente_ate is null
      order by vigente_desde desc, criado_em desc limit 1 for update;
      if not found or v_cpmv_atual.cpmv_unitario is distinct from v_item.cpmv_unitario then
        if found then
          update propostas_mhs.historico_cpmv_produtos
          set vigente_ate = case when vigente_desde < current_date then current_date - 1 else current_date end,
              atualizado_por = auth.uid(), atualizado_em = now()
          where historico_cpmv_id = v_cpmv_atual.historico_cpmv_id;
        end if;
        insert into propostas_mhs.historico_cpmv_produtos (
          item_catalogo_id, cpmv_unitario, vigente_desde, fonte, documento_referencia,
          observacao, criado_por, atualizado_por
        ) values (
          v_item.item_catalogo_id, v_item.cpmv_unitario, current_date, v_fonte,
          v_proposta_codigo, 'Valor unitario confirmado no salvamento da proposta.', auth.uid(), auth.uid()
        );
      end if;
    end if;

    if v_item.preco_distintos = 1 then
      select * into v_preco_atual
      from propostas_mhs.historico_precos_venda
      where item_catalogo_id = v_item.item_catalogo_id and vigente_ate is null
      order by vigente_desde desc, criado_em desc limit 1 for update;
      if not found or v_preco_atual.preco_venda_unitario is distinct from v_item.preco_venda_unitario then
        if found then
          update propostas_mhs.historico_precos_venda
          set vigente_ate = case when vigente_desde < current_date then current_date - 1 else current_date end,
              atualizado_por = auth.uid(), atualizado_em = now()
          where historico_preco_id = v_preco_atual.historico_preco_id;
        end if;
        insert into propostas_mhs.historico_precos_venda (
          item_catalogo_id, preco_venda_unitario, vigente_desde, fonte, observacao,
          criado_por, atualizado_por
        ) values (
          v_item.item_catalogo_id, v_item.preco_venda_unitario, current_date, v_fonte,
          'Preco unitario confirmado no salvamento da proposta.', auth.uid(), auth.uid()
        );
      end if;
    end if;
  end loop;
end;
$$;

notify pgrst, 'reload schema';
commit;
