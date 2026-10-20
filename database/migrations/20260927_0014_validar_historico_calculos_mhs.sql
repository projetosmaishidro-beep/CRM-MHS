-- ============================================================================
-- VALIDACAO SOMENTE-LEITURA - HISTORICO DE CALCULOS MHS
-- Execute depois de 20260927_0013_propostas_mhs_historico_calculos.sql.
-- ============================================================================

-- 1. Confirma a estrutura e as funcoes usadas pela interface.
select table_schema, table_name, column_name
from information_schema.columns
where table_schema = 'propostas_mhs'
  and table_name = 'memorias_calculo'
  and column_name = 'assinatura_calculo';

select routine_name
from information_schema.routines
where routine_schema = 'api'
  and routine_name in (
    'salvar_proposta_completa_com_historico_mhs',
    'registrar_memoria_calculo_proposta_mhs',
    'listar_memorias_calculo_proposta_mhs'
  )
order by routine_name;

-- 2. Confirma que somente usuarios autenticados podem executar as rotinas.
select
  has_function_privilege('authenticated', 'api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb)', 'EXECUTE') as autenticado_pode_salvar,
  has_function_privilege('anon', 'api.salvar_proposta_completa_com_historico_mhs(uuid, jsonb)', 'EXECUTE') as anon_pode_salvar;

-- 3. Mostra o historico recente e a quantidade de linhas gravadas em cada memoria.
select
  p.codigo as proposta,
  m.numero_calculo,
  m.situacao,
  m.base_calculo,
  m.fator_venda,
  m.valor_resultado,
  count(l.memoria_linha_id) as linhas_registradas,
  m.criado_em
from propostas_mhs.memorias_calculo m
join propostas_mhs.propostas p on p.proposta_id = m.proposta_id
left join propostas_mhs.memorias_calculo_linhas l on l.memoria_calculo_id = m.memoria_calculo_id
group by p.codigo, m.memoria_calculo_id
order by m.criado_em desc
limit 50;

-- 4. Evidencia os custos e precos atualmente gravados por item da proposta.
select
  p.codigo as proposta,
  g.ordem as ordem_grupo,
  i.ordem as ordem_item,
  i.descricao_comercial,
  i.quantidade,
  i.cpmv_unitario,
  i.cpmv_total,
  i.preco_venda_unitario,
  i.preco_venda_total,
  i.item_catalogo_id,
  (i.dados_adicionais ? 'mhs_ui_v1') as estrutura_completa_gravada
from propostas_mhs.propostas_itens i
join propostas_mhs.propostas p on p.proposta_id = i.proposta_id
left join propostas_mhs.propostas_grupos g on g.proposta_grupo_id = i.proposta_grupo_id
order by p.atualizado_em desc, g.ordem nulls last, i.ordem;

-- 5. Confere o historico global de CPMV gerado apenas para itens vinculados ao catalogo.
select
  c.codigo,
  c.nome,
  h.cpmv_unitario,
  h.vigente_desde,
  h.vigente_ate,
  h.fonte,
  h.documento_referencia,
  h.criado_em
from propostas_mhs.historico_cpmv_produtos h
join propostas_mhs.catalogo_itens c on c.item_catalogo_id = h.item_catalogo_id
order by h.criado_em desc
limit 50;
