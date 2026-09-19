# Análise da base completa do mapa

Fonte analisada: exportação CSV recebida em 19/09/2026. Os números abaixo são da fotografia entregue; eles devem ser reexecutados antes de uma carga futura.

## Retrato da base

| Indicador | Resultado |
| --- | ---: |
| Registros | 1.116 |
| Colunas de origem | 61 |
| CNPJ válido e único | 1.102 |
| Sem CNPJ válido | 14 |
| UUID técnico presente e único | 1.116 |
| Estados | 3 (`CE` 937, `RN` 142, `PI` 37) |
| Municípios | 50 |
| CNAEs | 84 |
| Situação ativa | 855 |
| Situação inapta | 244 |
| Situação não informada | 17 |

Os 17 registros de `CADASTRO_CAMPO` explicam toda a ausência de coordenada bruta; 14 deles ainda não possuem CNPJ válido. Eles não devem ser descartados: o UUID `cliente_id` é sua identidade de transição até a validação cadastral.

## Geografia

| Indicador | Resultado |
| --- | ---: |
| Registros com latitude/longitude bruta | 1.099 |
| Coordenadas brutas distintas | 44 |
| Registros em coordenadas repetidas | 1.097 |
| Localização confirmada em campo | 30 |
| Localização aproximada de sede municipal | 1.086 |

As coordenadas brutas são majoritariamente sedes municipais. Por exemplo, 247 registros compartilham o ponto de Jaguaruana e 165 o de Aracati. Elas são adequadas para planejamento regional, mas não para roteirização de porta em porta.

Há 13 registros cujo `localizacao_status` já é `CONFIRMADA_CAMPO`, enquanto o `geocode_status` histórico ainda permanece `APROX_SEDE_MUNICIPIO`. Isso é consistente com uma confirmação posterior de campo. A migração mantém a aproximação como histórico e usa a confirmação como ponto atual.

## Classificação comercial

`CNAE` é evidência de atividade econômica, não uma categoria CRM definitiva. A carga inicial deve classificar automaticamente somente quando a regra é inequívoca.

| Regra / fila | Registros | Tratamento |
| --- | ---: | --- |
| Criação de camarão em água salgada/salobra ou doce | 877 | `CARCINICULTOR`, confiança alta |
| Outra aquicultura ou pesca relacionada | 33 | revisão humana |
| Beneficiamento de pescados | 27 | revisão humana / papel `BENEFICIADOR` |
| Comércio de pescados | 53 | revisão humana / papel `COMERCIALIZADOR` |
| Construção civil direta | 9 | candidata a `CONSTRUCAO_CIVIL` |
| Extração mineral direta | 1 | candidata a `MINERACAO` |
| Gestão imobiliária candidata a condominial | 1 | revisão humana |
| Fornecedor de irrigação | 1 | revisão humana; não significa que seja irrigante |

Assim, `OUTRO` não é preenchido por descarte automático. Os 239 registros fora da regra de carcinicultura entram em uma fila explícita de classificação.

## Completude comercial

| Campo | Registros preenchidos |
| --- | ---: |
| Nome de contato | 5 |
| E-mail | 4 |
| Algum telefone/WhatsApp | 745 |
| WhatsApp | 17 |
| Observação comercial | 5 |
| Canal preferido | 0 |

Os dados jurídicos importados são aproveitáveis: datas de abertura não vazias estão válidas, capital social é convertível para número e só há um CEP preenchido fora do padrão de oito dígitos. `Sim`/`Não`/`0` de regimes tributários são normalizados para booleanos sem perder a fonte bruta.

## Decisões incorporadas na migração

1. `core.estabelecimentos` recebe CNPJ, abertura, porte, capital social, Simples, MEI e quantidade de sócios em tipos corretos.
2. `core.contatos` e `core.canais_contato` recebem pessoa/cargo e os canais de comunicação, sem limitar cada empresa a um telefone ou e-mail.
3. `core.localizacoes` guarda histórico de aproximação e confirmação de campo.
4. `core.estabelecimento_categorias` guarda categoria, fonte e confiança.
5. `crm.notas_conta` recebe observações comerciais; a tabela do mapa permanece focada em origem e geografia.
6. `integracao.referencias_origem` preserva cada `cliente_id` atual para que os aplicativos possam se relacionar sem depender do CNPJ.
