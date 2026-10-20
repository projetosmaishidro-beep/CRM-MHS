# Propostas MHS - Banco de dados e Storage

Este diretorio documenta o modulo de propostas da Mais Hidro. A estrutura usa o
contrato operacional atual do CRM: `cadastro`, `mapa`, `crm` e `api`.

> Nao execute estas migracoes junto da fundacao alternativa `core` de
> `20260919_0001_fundacao_unificada.sql`. A migracao operacional de
> `20260920_0002_api_operacional_supabase.sql` declara que os dois modelos sao
> incompatíveis; o modulo Propostas MHS segue o modelo ativo `cadastro/crm/api`.

## Ordem obrigatoria de processamento

1. Confirme que ja foram executados, nesta ordem:
   - `database/banco_simples/01_cadastro/01_cadastro.sql`;
   - `database/banco_simples/02_mapa/02_mapa.sql`;
   - `database/banco_simples/03_crm/03_crm.sql`;
   - `database/migrations/20260920_0002_api_operacional_supabase.sql`;
   - `database/migrations/20260922_0003_operacao_viagem.sql`.
2. Execute `database/migrations/20260927_0004_propostas_mhs_estrutura.sql`.
3. Execute `database/migrations/20260927_0005_propostas_mhs_regras.sql`.
4. Execute `database/migrations/20260927_0006_propostas_mhs_api_storage.sql`.
5. Execute `database/migrations/20260927_0007_propostas_mhs_operacoes.sql`.
6. Execute `database/migrations/20260927_0009_propostas_mhs_grupos_comerciais.sql`.
7. Execute `database/migrations/20260927_0010_propostas_mhs_recuperacao.sql`.
8. Execute `database/migrations/20260927_0011_propostas_mhs_templates_completos.sql`.
9. Execute, apenas para conferir, `database/migrations/20260927_0012_validar_integracao_mhs.sql`.
10. Execute `database/migrations/20260927_0013_propostas_mhs_historico_calculos.sql`.
11. Execute, apenas para conferir, `database/migrations/20260927_0014_validar_historico_calculos_mhs.sql`.
12. Execute `database/migrations/20260927_0015_propostas_mhs_numeracao_e_moeda.sql`.
13. Execute `database/migrations/20260927_0016_propostas_mhs_persistencia_emissao.sql`.
14. Execute, apenas para conferir, `database/migrations/20260927_0017_validar_emissao_persistencia_mhs.sql`.
15. Execute `database/migrations/20260927_0018_estabilizacao_operacional_propostas_mhs.sql`.
16. Execute `database/migrations/20260927_0019_templates_mhs_memoria_reutilizavel.sql`.
17. Execute `database/migrations/20260927_0020_propostas_mhs_arquivos_rascunho.sql`.
18. Execute `database/migrations/20260927_0021_propostas_mhs_integridade_revisao_atual.sql`.
19. Execute, apenas para conferir, `database/migrations/20260927_0022_validar_prontidao_operacional_mhs.sql`.
20. Execute `database/migrations/20260927_0023_templates_mhs_origem_versionada.sql`.
21. Execute `database/migrations/20260927_0024_templates_mhs_edicao_direta.sql`.
22. Execute `database/migrations/20260927_0025_galeria_pdfs_propostas_mhs.sql`.
23. Execute `database/migrations/20260927_0026_galeria_pdfs_propostas_agrupada.sql`.

`20260927_0008_validar_propostas_mhs.sql` permanece como validação da fundação inicial e pode ser executado depois do passo 5.

Todas as migracoes de estrutura e operacao sao aditivas. Os arquivos de validacao sao somente leitura.
Execute uma por vez no SQL Editor do Supabase, conferindo o `COMMIT` antes de
seguir para a proxima. Antes de producao, gere um backup no Supabase.

## Chave universal e dados de cliente

`cadastro.empresas.empresa_id` e a chave universal. Ela identifica o cliente no
CRM e no modulo de propostas. A tabela `propostas_mhs.clientes` e somente uma
extensao comercial: nao replica CNPJ, razao social, contatos nem endereco
oficial. Esses dados continuam no CRM e sao congelados em snapshot quando uma
revisao e emitida.

## Principais grupos de tabelas

| Grupo | Tabelas | Finalidade |
| --- | --- | --- |
| Cliente e obra | `clientes`, `locais_obra` | Vinculo CRM e varios locais de entrega/execucao. |
| Catalogo | `catalogo_itens`, `catalogo_composicoes`, `catalogo_composicoes_versoes`, `catalogo_composicao_componentes` | Produtos, servicos e conjuntos com composicao versionada. |
| Custos | `historico_cpmv_produtos`, `historico_precos_venda` | Vigencia, fonte e rastreabilidade de CPMV/preco. |
| Proposta | `propostas`, `propostas_itens`, `propostas_itens_composicao` | Rascunho comercial atual e fornecimentos. |
| Calculo | `memorias_calculo`, `memorias_calculo_linhas` | Impostos, margens, lucro, financeiro, prazo e fator de venda. |
| Condicoes | `propostas_condicoes`, `propostas_pagamentos`, `propostas_escopo`, `propostas_referencias` | Frete, validade, garantia, pagamentos, incluso/nao incluso e links. |
| Reuso | `blocos_inteligentes`, `blocos_inteligentes_versoes`, `templates`, `templates_versoes` | Textos tecnicos e templates recuperaveis e versionados. |
| Historico | `propostas_revisoes`, `historico_acoes` | Snapshot imutavel, hash de integridade, usuario e antes/depois. |
| Arquivos | `arquivos_proposta`, `arquivos_template` | Metadados, checksum e referencia ao Storage privado. |

## Regras de persistencia

- Propostas usam codigo sequencial anual como `AA.NNN`.
- Valores de CPMV, preco e memoria usam `numeric`, nunca ponto flutuante.
- Cada revisao recebe snapshot completo e hash; ela nao pode ser alterada ou
  excluida.
- Mudanca de CPMV ou preco fecha a vigencia anterior e cria outro registro.
- Toda alteracao relevante gera registro em `historico_acoes` com usuario,
  momento e conteudo antes/depois.
- Templates removem cliente, obra e identificadores comerciais da proposta de
  origem antes de persistir.
- Escrita do navegador ocorre apenas por funcoes `api.*`; as tabelas do schema
  `propostas_mhs` ficam privadas com RLS habilitado.
- O total, fator e memoria oficial sao recalculados a partir dos grupos e itens
  persistidos; o autosave nao atualiza o catalogo mestre.
- Uma proposta so pode ser finalizada quando o PDF da revisao estiver registrado
  e confirmado no bucket privado.

## Rotas oficiais do Storage

Bucket privado: `propostas-mhs` (limite de 50 MB por arquivo).

```text
clientes/{empresa_id}/propostas/{proposta_id}/revisoes/R{numero}/pdf/{arquivo}.pdf
clientes/{empresa_id}/propostas/{proposta_id}/revisoes/R{numero}/anexos/{arquivo}
clientes/{empresa_id}/propostas/{proposta_id}/revisoes/R{numero}/imagens/{arquivo}
clientes/{empresa_id}/propostas/{proposta_id}/revisoes/R{numero}/tecnicos/{arquivo}
clientes/{empresa_id}/propostas/{proposta_id}/rascunhos/{anexos|imagens|tecnicos}/{arquivo}
templates/{template_id}/versoes/V{numero}/anexos/{arquivo}
templates/{template_id}/versoes/V{numero}/imagens/{arquivo}
templates/{template_id}/versoes/V{numero}/tecnicos/{arquivo}
```

Depois do upload, registre os metadados por
`api.registrar_arquivo_proposta_mhs` ou
`api.registrar_arquivo_template_mhs`. PDF gerado exige uma revisao e deve ficar
na pasta `pdf` da revisao correspondente. Arquivos de rascunho sao preservados
antes da emissao e, ao emitir, sao copiados para a revisao e arquivados na rota
temporaria.

## Funcoes que o front-end deve usar

- `api.criar_proposta_mhs(jsonb)` cria o cabecalho e a numeracao.
- `api.salvar_conteudo_proposta_mhs(uuid, jsonb)` salva itens, componentes,
  condicoes, pagamentos, escopo, referencias, blocos e memoria em transacao.
- `api.criar_revisao_proposta_mhs(uuid, text, text)` congela uma revisao.
- `api.confirmar_revisao_proposta_mhs(uuid, uuid)` confirma o PDF no bucket
  antes da finalizacao.
- `api.detalhar_proposta_mhs(uuid)` e `api.detalhar_revisao_proposta_mhs(uuid)`
  recuperam rascunho atual e snapshot historico.
- `api.registrar_cpmv_mhs(jsonb)` e `api.registrar_preco_venda_mhs(jsonb)`
  preservam a vigencia do custo/preco anterior.
- `api.salvar_template_proposta_mhs(...)` cria ou versiona templates sem dados
  do cliente; `api.obter_template_proposta_mhs(...)` recupera uma versao.
- `api.salvar_bloco_inteligente_mhs(jsonb)` versiona textos tecnicos e blocos.

As views `api.vw_*_mhs` atendem listas e filtros. Somente usuarios membros da
equipe, definidos em `cadastro.equipe`, podem consultar; editores e
administradores podem gravar.


