-- ============================================================================
-- VALIDAÇÃO DA API DE LEITURA
-- Execute depois de 01_api_leitura_autenticada.sql.
-- Todas as consultas abaixo são somente leitura.
-- ============================================================================

-- A carteira deve refletir a classificação já validada na migração.
select
    tipo_relacionamento,
    count(*) as empresas
from api.vw_carteira_crm
group by tipo_relacionamento
order by tipo_relacionamento;

-- Para a primeira carga de carcinicultura, o esperado é 12 CLIENTE e 865 LEAD.
select
    categoria,
    tipo_relacionamento,
    count(*) as empresas
from api.vw_carteira_crm
group by categoria, tipo_relacionamento
order by categoria, tipo_relacionamento;

-- O mapa deve receber o mesmo número de linhas da carteira e preservar a
-- condição de confirmação do ponto.
select
    localizacao_status,
    count(*) as empresas
from api.vw_mapa_clientes
group by localizacao_status
order by localizacao_status;

-- Simula a leitura que será feita por um usuário autenticado. A transação é
-- revertida no fim: não grava nem altera a sessão do projeto.
begin;
set local role authenticated;

select count(*) as carteira_visivel_para_equipe
from api.vw_carteira_crm;

select count(*) as pontos_visiveis_para_equipe
from api.vw_mapa_clientes;

rollback;
