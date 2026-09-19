# Banco unificado simples

Esta é a arquitetura a ser usada no novo projeto Supabase. Ela não altera o
banco atual do mapa e não depende da pasta de migrações anterior.

## Ordem de execução

1. `01_cadastro/01_cadastro.sql`
2. `02_mapa/02_mapa.sql`
3. `03_crm/03_crm.sql`
4. `04_regras/04_sincronizacao_mapa_crm.sql`
5. `05_armazenamento/05_buckets_privados.sql`
6. `06_validacao/06_validar_estrutura.sql`
7. `07_migracao_carcinicultura/01_criar_origem_csv.sql`, depois o CSV e
   `07_migracao_carcinicultura/02_importar_carcinicultores.sql`

## Três schemas, uma identidade

| Schema | O que guarda | Não guarda |
| --- | --- | --- |
| `cadastro` | ficha única da empresa, contatos e histórico de auditoria | visitas, despesas e arquivos |
| `mapa` | ponto, confirmação, origem e evidências geográficas | etapa comercial |
| `crm` | lead/cliente, viagens, visitas, necessidades, despesas e anexos | CNPJ e endereço duplicados |

Cada empresa recebe um `empresa_id`. Esse é o identificador usado pelo mapa e
pelo CRM; nome, CNPJ, endereço e contato existem uma única vez em
`cadastro.empresas`.

## Regra principal

| Status do ponto no mapa | Tipo no CRM |
| --- | --- |
| `CONFIRMADO_CAMPO`, com latitude e longitude | `CLIENTE` |
| `APROXIMADO_MUNICIPIO`, `PENDENTE` ou `AMBIGUO` | `LEAD` |

A regra é aplicada por um gatilho pequeno no arquivo `04_regras`. Uma mudança
de ponto preserva o mesmo `empresa_id`, o histórico de visitas e os anexos.

Para a classificação automática, "confirmado" significa obrigatoriamente:

1. `status_confirmacao = CONFIRMADO_CAMPO`;
2. latitude e longitude preenchidas;
3. confirmação registrada pelo operador no mapa ou identificador do operador
   legado preservado durante a migração.

Qualquer outro caso vira ou permanece `LEAD`. A data da primeira promoção a
cliente é mantida mesmo se o ponto precisar voltar a lead; a mudança completa
fica registrada no histórico.

## Categorias de empresa

A categoria é uma única coluna simples em `cadastro.empresas`:

`CARCINICULTOR`, `IRRIGACAO`, `CONSTRUCAO_CIVIL`, `MINERACAO`, `CONDOMINIAL`,
`OUTRO` ou `PENDENTE_CLASSIFICACAO`.

## Segurança

Os schemas e os buckets são privados por padrão. A carga inicial deve ser feita
no SQL Editor ou por um processo administrativo. As políticas de acesso da
equipe e as RPCs do aplicativo entram em uma etapa posterior, antes de conectar
os aplicativos ao banco novo.

## Histórico e auditoria

`cadastro.historico` é uma tabela única para auditoria. Ela registra alterações
em empresa, ponto, relacionamento CRM, viagem, visita, necessidade, despesa e
anexo. Cada registro informa tabela de origem, ação, ID do registro, dados antes,
dados depois, usuário, origem (`USUARIO` ou `SISTEMA`) e data. Ela não é usada
pelas telas comuns; existe para consulta de histórico e auditoria.
