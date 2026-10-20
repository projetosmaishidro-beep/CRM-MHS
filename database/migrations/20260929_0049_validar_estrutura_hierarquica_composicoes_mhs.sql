-- Validacao somente-leitura. Execute depois da migracao 0048.

select routine_name
from information_schema.routines
where routine_schema in ('api', 'propostas_mhs')
  and routine_name in (
    'sincronizar_estrutura_composicao_proposta_mhs',
    'inserir_linha_estrutura_composicao_mhs',
    'salvar_proposta_transacional_mhs'
  )
order by routine_schema, routine_name;

-- Todos os itens-cabeca modulados devem pertencer ao grupo do respectivo modulo.
select count(*) as itens_com_modulo_invalido
from propostas_mhs.propostas_itens i
join propostas_mhs.propostas_composicao_modulos m
  on m.proposta_composicao_modulo_id = i.proposta_composicao_modulo_id
where i.proposta_grupo_id is distinct from m.proposta_grupo_id;

-- Todo subitem-pai deve pertencer ao mesmo item-cabeca que seu filho.
select count(*) as subitens_com_pai_invalido
from propostas_mhs.propostas_itens_composicao filho
join propostas_mhs.propostas_itens_composicao pai
  on pai.proposta_item_composicao_id = filho.proposta_item_composicao_pai_id
where filho.proposta_item_id <> pai.proposta_item_id;

-- Inspecao da arvore gravada, ordenada por modulo, item-cabeca e nivel.
with recursive arvore as (
  select i.proposta_id, m.codigo as modulo, i.codigo_referencia as item_cabeca,
         c.proposta_item_composicao_id, c.proposta_item_composicao_pai_id,
         c.codigo_referencia as subitem, c.descricao, c.unidade, c.quantidade,
         c.cpmv_unitario, c.cpmv_total, c.incluir_no_cpmv, 1 as nivel,
         lpad(c.ordem::text, 6, '0') as caminho
  from propostas_mhs.propostas_itens_composicao c
  join propostas_mhs.propostas_itens i on i.proposta_item_id = c.proposta_item_id
  join propostas_mhs.propostas_composicao_modulos m on m.proposta_composicao_modulo_id = i.proposta_composicao_modulo_id
  where c.proposta_item_composicao_pai_id is null
  union all
  select a.proposta_id, a.modulo, a.item_cabeca,
         c.proposta_item_composicao_id, c.proposta_item_composicao_pai_id,
         c.codigo_referencia, c.descricao, c.unidade, c.quantidade,
         c.cpmv_unitario, c.cpmv_total, c.incluir_no_cpmv, a.nivel + 1,
         a.caminho || '.' || lpad(c.ordem::text, 6, '0')
  from arvore a
  join propostas_mhs.propostas_itens_composicao c
    on c.proposta_item_composicao_pai_id = a.proposta_item_composicao_id
)
select proposta_id, modulo, item_cabeca, nivel, subitem, descricao, unidade,
       quantidade, cpmv_unitario, cpmv_total, incluir_no_cpmv
from arvore
order by proposta_id, modulo, item_cabeca, caminho;
