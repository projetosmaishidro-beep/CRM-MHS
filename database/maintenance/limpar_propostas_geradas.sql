-- ============================================================================
-- MANUTENCAO CONTROLADA - LIMPAR SOMENTE PROPOSTAS E RASCUNHOS
--
-- NAO e uma migracao. Execute manualmente no SQL Editor somente depois de:
--   1. criar e validar um backup;
--   2. remover pelo Storage API/Dashboard a pasta `clientes` do bucket
--      `propostas-mhs` (nao remova a pasta `templates`);
--   3. conferir a pre-visualizacao abaixo;
--   4. trocar v_confirmar para true no bloco destrutivo.
--
-- Preserva: clientes/CRM, locais, catalogo, historicos de CPMV/preco,
-- composicoes de catalogo, textos tecnicos, templates, arquivos de template,
-- conjuntos reutilizaveis, frases prontas e modelos de encerramento.
-- Remove: propostas/rascunhos, itens, grupos, condicoes, pagamentos, escopo,
-- referencias, blocos aplicados, memorias de calculo vinculadas a propostas,
-- comissoes, revisoes, estados de emissao, metadados de arquivos e auditoria
-- exclusivamente vinculada aos registros removidos.
-- ============================================================================

-- --------------------------------------------------------------------------
-- 1. PRE-VISUALIZACAO (somente leitura)
-- --------------------------------------------------------------------------
select 'propostas' as objeto, count(*)::bigint as quantidade
from propostas_mhs.propostas
union all
select 'rascunhos', count(*)::bigint
from propostas_mhs.propostas
where status in ('RASCUNHO', 'EM_EDICAO')
union all
select 'revisoes', count(*)::bigint
from propostas_mhs.propostas_revisoes
union all
select 'arquivos_metadados', count(*)::bigint
from propostas_mhs.arquivos_proposta
union all
select 'objetos_storage_de_propostas', count(*)::bigint
from storage.objects
where bucket_id = 'propostas-mhs'
  and name ~ '^clientes/[^/]+/propostas/[^/]+/'
order by objeto;

-- Caminhos que ainda precisam ser excluidos pelo Storage API/Dashboard.
-- Esta consulta e somente leitura: nunca apague storage.objects por SQL.
select bucket_id, name as caminho_storage
from storage.objects
where bucket_id = 'propostas-mhs'
  and name ~ '^clientes/[^/]+/propostas/[^/]+/'
order by name;

-- --------------------------------------------------------------------------
-- 2. LIMPEZA TRANSACIONAL DO BANCO
-- --------------------------------------------------------------------------
begin;

set local lock_timeout = '5s';
set local statement_timeout = '5min';

do $$
declare
  -- TRAVA MANUAL: altere para true somente depois do backup e do Storage vazio.
  v_confirmar constant boolean := false;
begin
  if not v_confirmar then
    raise exception 'LIMPEZA BLOQUEADA: altere v_confirmar para true depois do backup e da remocao dos arquivos pelo Storage API.';
  end if;

  if exists (
    select 1
    from storage.objects
    where bucket_id = 'propostas-mhs'
      and name ~ '^clientes/[^/]+/propostas/[^/]+/'
  ) then
    raise exception 'LIMPEZA BLOQUEADA: ainda existem arquivos de propostas no bucket. Remova-os pelo Storage API/Dashboard, nunca por SQL.';
  end if;
end;
$$;

-- Registra os totais das bibliotecas que obrigatoriamente devem permanecer.
create temporary table _bibliotecas_preservadas (
  relacao regclass primary key,
  quantidade_antes bigint not null
) on commit drop;

insert into _bibliotecas_preservadas (relacao, quantidade_antes) values
  ('propostas_mhs.clientes'::regclass, (select count(*) from propostas_mhs.clientes)),
  ('propostas_mhs.locais_obra'::regclass, (select count(*) from propostas_mhs.locais_obra)),
  ('propostas_mhs.catalogo_itens'::regclass, (select count(*) from propostas_mhs.catalogo_itens)),
  ('propostas_mhs.catalogo_composicoes'::regclass, (select count(*) from propostas_mhs.catalogo_composicoes)),
  ('propostas_mhs.catalogo_composicoes_versoes'::regclass, (select count(*) from propostas_mhs.catalogo_composicoes_versoes)),
  ('propostas_mhs.catalogo_composicao_componentes'::regclass, (select count(*) from propostas_mhs.catalogo_composicao_componentes)),
  ('propostas_mhs.historico_cpmv_produtos'::regclass, (select count(*) from propostas_mhs.historico_cpmv_produtos)),
  ('propostas_mhs.historico_precos_venda'::regclass, (select count(*) from propostas_mhs.historico_precos_venda)),
  ('propostas_mhs.blocos_inteligentes'::regclass, (select count(*) from propostas_mhs.blocos_inteligentes)),
  ('propostas_mhs.blocos_inteligentes_versoes'::regclass, (select count(*) from propostas_mhs.blocos_inteligentes_versoes)),
  ('propostas_mhs.templates'::regclass, (select count(*) from propostas_mhs.templates)),
  ('propostas_mhs.templates_versoes'::regclass, (select count(*) from propostas_mhs.templates_versoes)),
  ('propostas_mhs.arquivos_template'::regclass, (select count(*) from propostas_mhs.arquivos_template)),
  ('propostas_mhs.conjuntos_reutilizaveis'::regclass, (select count(*) from propostas_mhs.conjuntos_reutilizaveis)),
  ('propostas_mhs.frases_prontas_observacoes'::regclass, (select count(*) from propostas_mhs.frases_prontas_observacoes)),
  ('propostas_mhs.modelos_encerramento_proposta'::regclass, (select count(*) from propostas_mhs.modelos_encerramento_proposta));

-- Identificadores usados para remover somente a auditoria das propostas.
create temporary table _historico_alvo (
  entidade text not null,
  entidade_id uuid not null,
  primary key (entidade, entidade_id)
) on commit drop;

insert into _historico_alvo
select 'PROPOSTA', proposta_id from propostas_mhs.propostas
union all
select 'propostas_mhs.propostas', proposta_id from propostas_mhs.propostas
union all
select 'propostas_mhs.propostas_itens', proposta_item_id from propostas_mhs.propostas_itens
union all
select 'propostas_mhs.propostas_itens_composicao', proposta_item_composicao_id from propostas_mhs.propostas_itens_composicao
union all
select 'propostas_mhs.memorias_calculo', memoria_calculo_id from propostas_mhs.memorias_calculo
union all
select 'MEMORIA_CALCULO', memoria_calculo_id from propostas_mhs.memorias_calculo
union all
select 'propostas_mhs.propostas_revisoes', revisao_id from propostas_mhs.propostas_revisoes
union all
select 'ARQUIVO_PROPOSTA', arquivo_id from propostas_mhs.arquivos_proposta;

-- A imutabilidade continua ativa no sistema; e suspensa apenas nesta transacao
-- para permitir a limpeza administrativa integral das revisoes selecionadas.
alter table propostas_mhs.propostas_revisoes
  disable trigger revisoes_imutaveis;

delete from propostas_mhs.propostas_revisoes_emissao;
delete from propostas_mhs.arquivos_proposta;
delete from propostas_mhs.propostas_revisoes;

alter table propostas_mhs.propostas_revisoes
  enable trigger revisoes_imutaveis;

-- Dependencias operacionais. Nenhuma biblioteca compartilhada aparece aqui.
delete from propostas_mhs.propostas_comissoes;
delete from propostas_mhs.propostas_blocos;
delete from propostas_mhs.propostas_escopo;
delete from propostas_mhs.propostas_pagamentos;
delete from propostas_mhs.propostas_condicoes;
delete from propostas_mhs.propostas_referencias;
delete from propostas_mhs.memorias_calculo;
delete from propostas_mhs.propostas_grupos;
delete from propostas_mhs.propostas_opcoes_comerciais;
delete from propostas_mhs.propostas;

-- A numeracao volta ao estado inicial, coerente com uma base sem propostas.
delete from propostas_mhs.numeracao_anual;

-- Remove rastros somente dos registros capturados antes da limpeza.
delete from propostas_mhs.historico_acoes h
using _historico_alvo a
where h.entidade = a.entidade
  and h.entidade_id = a.entidade_id;

-- Pos-condicoes: qualquer divergencia desfaz toda a transacao.
do $$
declare
  v_registro record;
  v_quantidade_depois bigint;
begin
  if exists (select 1 from propostas_mhs.propostas)
    or exists (select 1 from propostas_mhs.propostas_revisoes)
    or exists (select 1 from propostas_mhs.propostas_revisoes_emissao)
    or exists (select 1 from propostas_mhs.arquivos_proposta)
    or exists (select 1 from propostas_mhs.propostas_itens)
    or exists (select 1 from propostas_mhs.propostas_itens_composicao)
    or exists (select 1 from propostas_mhs.propostas_grupos)
    or exists (select 1 from propostas_mhs.propostas_opcoes_comerciais)
    or exists (select 1 from propostas_mhs.propostas_comissoes)
    or exists (select 1 from propostas_mhs.propostas_condicoes)
    or exists (select 1 from propostas_mhs.propostas_pagamentos)
    or exists (select 1 from propostas_mhs.propostas_escopo)
    or exists (select 1 from propostas_mhs.propostas_referencias)
    or exists (select 1 from propostas_mhs.propostas_blocos)
    or exists (select 1 from propostas_mhs.memorias_calculo)
    or exists (select 1 from propostas_mhs.memorias_calculo_linhas) then
    raise exception 'A limpeza ficou incompleta; toda a transacao sera revertida.';
  end if;

  for v_registro in select * from _bibliotecas_preservadas loop
    execute format('select count(*) from %s', v_registro.relacao)
      into v_quantidade_depois;
    if v_quantidade_depois <> v_registro.quantidade_antes then
      raise exception 'A biblioteca % foi alterada (% antes, % depois). Toda a transacao sera revertida.',
        v_registro.relacao, v_registro.quantidade_antes, v_quantidade_depois;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_trigger t
    where t.tgrelid = 'propostas_mhs.propostas_revisoes'::regclass
      and t.tgname = 'revisoes_imutaveis'
      and t.tgenabled = 'O'
      and not t.tgisinternal
  ) then
    raise exception 'A protecao das revisoes nao foi reativada; toda a transacao sera revertida.';
  end if;
end;
$$;

commit;

-- --------------------------------------------------------------------------
-- 3. CONFERENCIA FINAL (deve retornar somente zeros)
-- --------------------------------------------------------------------------
select 'propostas' as objeto, count(*)::bigint as quantidade
from propostas_mhs.propostas
union all
select 'revisoes', count(*)::bigint from propostas_mhs.propostas_revisoes
union all
select 'arquivos_metadados', count(*)::bigint from propostas_mhs.arquivos_proposta
union all
select 'objetos_storage_de_propostas', count(*)::bigint
from storage.objects
where bucket_id = 'propostas-mhs'
  and name ~ '^clientes/[^/]+/propostas/[^/]+/'
order by objeto;
