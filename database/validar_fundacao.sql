-- Execute após 20260919_0001_fundacao_unificada.sql.
-- Nenhuma consulta abaixo altera dados.

-- 1. Todo registro do mapa deve manter uma referência para o cadastro canônico.
select
    (select count(*) from mapa_clientes.base_mapa) as registros_legados,
    (select count(*) from integracao.referencias_origem
      where sistema = 'MAPA_CLIENTES_LEGADO' and tipo_entidade = 'CLIENTE') as referencias_migradas,
    (select count(*) from core.estabelecimentos where origem_principal = 'MAPA_CLIENTES') as estabelecimentos_canonicos;

-- 2. Nenhum CNPJ válido pode aparecer duas vezes no cadastro mestre.
select cnpj_normalizado, count(*)
from core.estabelecimentos
where cnpj_normalizado is not null
group by cnpj_normalizado
having count(*) > 1;

-- 3. A qualidade da coordenada é explícita. Aproximação de município não pode
-- ser contada como ponto confirmado em indicadores de visita/roteirização fina.
select qualidade, fonte, count(*)
from core.localizacoes
group by qualidade, fonte
order by qualidade, fonte;

-- 4. Categoria só é automática onde a regra tem evidência objetiva.
select
    coalesce(cat.nome, 'Sem categoria principal') as categoria,
    ec.fonte,
    ec.confianca,
    count(*)
from core.estabelecimentos e
left join core.estabelecimento_categorias ec
    on ec.estabelecimento_id = e.estabelecimento_id and ec.principal
left join core.categorias_clientes cat on cat.categoria_id = ec.categoria_id
group by coalesce(cat.nome, 'Sem categoria principal'), ec.fonte, ec.confianca
order by categoria;

-- 5. Fila que precisa de revisão comercial humana.
select *
from mapa_clientes.vw_fila_classificacao
order by uf, municipio, nome;

-- 6. Nenhuma tabela canônica deve estar disponível ao papel anônimo.
select table_schema, table_name, privilege_type, grantee
from information_schema.role_table_grants
where table_schema in ('core', 'crm', 'integracao')
  and grantee = 'anon'
order by table_schema, table_name, privilege_type;
