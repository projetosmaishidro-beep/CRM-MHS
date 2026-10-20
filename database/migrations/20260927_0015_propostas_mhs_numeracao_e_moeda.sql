-- ============================================================================
-- PROPOSTAS MHS - NUMERACAO COMERCIAL ANUAL E VALORES EM REAIS
--
-- Execute depois de 20260927_0014_validar_historico_calculos_mhs.sql.
-- Regra oficial: AA.NNN (ex.: 26.000). A sequencia e reiniciada por ano.
-- ============================================================================

begin;

-- Preserva o identificador gerado pelo formato anterior sem alterar nenhum
-- registro historico. O novo codigo comercial passa a ser a coluna `codigo`.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'propostas_mhs' and table_name = 'propostas' and column_name = 'codigo'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'propostas_mhs' and table_name = 'propostas' and column_name = 'codigo_legado'
  ) then
    alter table propostas_mhs.propostas rename column codigo to codigo_legado;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'propostas_mhs' and table_name = 'propostas' and column_name = 'codigo'
  ) then
    alter table propostas_mhs.propostas
      add column codigo text generated always as (
        lpad((ano % 100)::text, 2, '0') || '.' || lpad(numero_sequencial::text, 3, '0')
      ) stored;
  end if;
end;
$$;

comment on column propostas_mhs.propostas.codigo is
  'Codigo comercial oficial no formato AA.NNN. Ex.: a proposta sequencial 0 de 2026 e 26.000; em 2027 a primeira e 27.000.';
comment on column propostas_mhs.propostas.codigo_legado is
  'Identificador preservado do formato anterior, somente para rastreabilidade de registros ja existentes.';

-- A API volta a expor o codigo comercial como `codigo`, sem expor a coluna
-- legada ao navegador.
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

-- O contador anual e base-zero: o primeiro projeto do ano recebe NNN = 000.
alter table propostas_mhs.propostas
  drop constraint if exists propostas_numero_check;
alter table propostas_mhs.propostas
  add constraint propostas_numero_check check (numero_sequencial >= 0);

create or replace function propostas_mhs.proximo_numero_proposta(
  p_ano integer default extract(year from current_date)::integer
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, propostas_mhs
as $$
declare
  v_numero integer;
begin
  if p_ano not between 2000 and 2200 then
    raise exception 'Ano de proposta invalido: %', p_ano using errcode = '22023';
  end if;

  insert into propostas_mhs.numeracao_anual (ano, ultimo_numero)
  values (p_ano, 0)
  on conflict (ano) do update
    set ultimo_numero = propostas_mhs.numeracao_anual.ultimo_numero + 1,
        atualizado_em = now()
  returning ultimo_numero into v_numero;

  return v_numero;
end;
$$;

-- Valores monetarios sao sempre numericos em reais (BRL); por exemplo,
-- 1250.5000 significa R$ 1.250,50. Nao ha conversao para centavos inteiros.
comment on column propostas_mhs.propostas.valor_cpmv_total is 'CPMV total em reais (BRL), com quatro casas decimais para calculo.';
comment on column propostas_mhs.propostas.valor_base_calculo is 'Base de calculo em reais (BRL), com quatro casas decimais para calculo.';
comment on column propostas_mhs.propostas.valor_proposta is 'Preco total da proposta em reais (BRL), com quatro casas decimais para calculo.';
comment on column propostas_mhs.propostas_itens.cpmv_unitario is 'CPMV unitario em reais (BRL), nunca em centavos.';
comment on column propostas_mhs.propostas_itens.cpmv_total is 'CPMV total do item em reais (BRL), nunca em centavos.';
comment on column propostas_mhs.propostas_itens.preco_venda_unitario is 'Preco unitario de venda em reais (BRL), nunca em centavos.';
comment on column propostas_mhs.propostas_itens.preco_venda_total is 'Preco total de venda em reais (BRL), nunca em centavos.';

notify pgrst, 'reload schema';
commit;
