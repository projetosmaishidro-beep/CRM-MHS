-- Validacao somente-leitura. Execute depois da migracao 0044.

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name = 'sincronizar_local_cadastral_proposta_mhs';

select tgname
from pg_trigger
where tgrelid = 'propostas_mhs.propostas'::regclass
  and tgname = 'propostas_promover_historico_catalogo_finalizacao'
  and not tgisinternal;

-- A proposta recem-salva deve ter local_obra_id preenchido. Propostas legadas
-- anteriores a 0044 podem continuar nulas ate serem salvas novamente.
select p.proposta_id, p.codigo, p.atualizado_em, p.local_obra_id,
       l.nome as local_nome, l.logradouro, l.municipio, l.uf, l.cep
from propostas_mhs.propostas p
left join propostas_mhs.locais_obra l on l.local_obra_id = p.local_obra_id
order by p.atualizado_em desc
limit 20;

-- Itens finalizados, vinculados ao catalogo e sem negociacao ambigua devem
-- possuir o valor vigente no historico global.
select itens.proposta_id, itens.item_catalogo_id,
       itens.cpmv_unitario as cpmv_proposta,
       c.cpmv_unitario as cpmv_historico_vigente,
       itens.preco_venda_unitario as preco_proposta,
       v.preco_venda_unitario as preco_historico_vigente
from (
  select p.proposta_id, i.item_catalogo_id,
         min(i.cpmv_unitario) as cpmv_unitario,
         min(i.preco_venda_unitario) as preco_venda_unitario
  from propostas_mhs.propostas p
  join propostas_mhs.propostas_itens i on i.proposta_id = p.proposta_id and i.ativo
  where p.status = 'FINALIZADA' and i.item_catalogo_id is not null
  group by p.proposta_id, i.item_catalogo_id
  having count(distinct i.cpmv_unitario) = 1
     and count(distinct i.preco_venda_unitario) = 1
) itens
left join propostas_mhs.historico_cpmv_produtos c
  on c.historico_cpmv_id = (
    select historico_cpmv_id
    from propostas_mhs.historico_cpmv_produtos
    where item_catalogo_id = itens.item_catalogo_id
      and cpmv_unitario = itens.cpmv_unitario
    order by criado_em desc
    limit 1
  )
left join propostas_mhs.historico_precos_venda v
  on v.historico_preco_id = (
    select historico_preco_id
    from propostas_mhs.historico_precos_venda
    where item_catalogo_id = itens.item_catalogo_id
      and preco_venda_unitario = itens.preco_venda_unitario
    order by criado_em desc
    limit 1
  )
order by itens.proposta_id, itens.item_catalogo_id;
