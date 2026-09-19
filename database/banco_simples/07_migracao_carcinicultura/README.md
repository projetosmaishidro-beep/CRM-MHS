# Migração inicial — carcinicultura

Esta é a primeira carga do novo banco. Ela traz somente empresas cujo CNAE é:

- `321302` — criação de camarões em água salgada e salobra;
- `322102` — criação de camarões em água doce.

Na base completa analisada, o resultado esperado é:

| Resultado | Total esperado |
| --- | ---: |
| Empresas de carcinicultura | 877 |
| Clientes com ponto confirmado | 12 |
| Leads com ponto aproximado ou pendente | 865 |
| CNPJ válido | 877 |

## Ordem segura

1. Execute os arquivos `01` a `05` da pasta principal `banco_simples`.
2. Execute `01_criar_origem_csv.sql` desta pasta.
3. Envie o CSV completo para o bucket privado no caminho:
   `importacoes-privadas/mapa/2026-09-19/base-completa-mapa.csv`.
4. Importe o mesmo CSV para `mapa.origem_carcinicultura_csv` pelo Table Editor.
   A tabela foi criada com os mesmos cabeçalhos da exportação atual.
5. Execute `02_importar_carcinicultores.sql` uma única vez.
6. Execute `03_validar_migracao.sql`. A consulta de inconsistências deve retornar
   zero linhas antes de conectar qualquer aplicativo.

## O que a carga faz

- Cria uma empresa em `cadastro.empresas` com categoria `CARCINICULTOR`.
- Cria um ponto em `mapa.pontos`.
- Deixa o gatilho decidir `LEAD` ou `CLIENTE` no CRM.
- Preserva o UUID antigo em `cliente_id_legado`.
- Guarda o ID do operador antigo em `confirmado_por_legado`; ele não depende de
  um usuário já existente no novo Supabase.
- Registra arquivo, lote e linha de origem para auditoria.

A tabela `mapa.origem_carcinicultura_csv` é exclusiva da migração: não é usada
pelos aplicativos. Ela permanece privada até a conferência final, junto com o
CSV original armazenado no bucket.
