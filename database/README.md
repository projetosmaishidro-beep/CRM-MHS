# Banco unificado — fundação

Esta pasta prepara o banco Supabase novo que será compartilhado pelos dois
aplicativos, sem fundi-los em uma única interface.

## Limites de responsabilidade

| Schema | Dono do dado | Responsabilidade |
| --- | --- | --- |
| `core` | Base comum | empresa, estabelecimento, endereço, contato, CNAE e classificações |
| `mapa_clientes` | Aplicativo de mapa | importações, tentativas de geocodificação e consultas geográficas |
| `crm` | Central comercial | conta, oportunidade, visita, viagem, necessidade, despesa e anexo |
| `integracao` | Integração | chaves externas e eventos entre os aplicativos |

`mapa_clientes.base_mapa` continua sendo a fonte bruta da importação. Ela não é
mais o cadastro mestre comercial. O cadastro mestre passa a ser
`core.estabelecimentos`, identificado por CNPJ quando houver.

## Ordem de implantação

1. Crie o novo projeto Supabase e habilite a extensão `pgcrypto`.
2. Importe a estrutura e os dados legados do mapa em `mapa_clientes.base_mapa`
   (as migrações atuais do mapa fazem isso).
3. Execute `migrations/20260919_0001_fundacao_unificada.sql`.
4. Execute `validar_fundacao.sql` e confira as views `mapa_clientes.vw_clientes_mapa` e
   `mapa_clientes.vw_fila_classificacao`.
5. Só então conecte primeiro o mapa e, em seguida, o CRM por RPCs/visões
   controladas. Não exponha tabelas brutas para `anon`.

A migração é aditiva e pode ser executada novamente. Ela não apaga
`base_mapa`, nem troca coordenadas aproximadas por coordenadas confirmadas.

O retrato e as decisões extraídas da exportação completa estão em
[`ANALISE_BASE_COMPLETA.md`](ANALISE_BASE_COMPLETA.md).

## Categorias

Categoria comercial não é o mesmo que CNAE. Uma empresa pode ter várias
classificações e cada vínculo registra fonte e confiança. A carga inicial só
classifica automaticamente como `CARCINICULTOR` os CNAEs que descrevem criação
de camarão; os demais entram na fila de revisão em vez de receberem `OUTRO`
indevidamente.

## Segurança

A fundação fecha o acesso público e deixa a leitura/escrita para a próxima
camada de autenticação/RPC. Assim, dados empresariais, contatos e observações
comerciais não voltam a ficar publicamente acessíveis como ocorre hoje na
tabela de mapa.
