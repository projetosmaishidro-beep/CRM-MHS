# Conexão dos aplicativos ao Supabase

Esta etapa prepara a conexão no navegador. A conexão isolada **não libera
tabelas**; depois da autenticação e da liberação da API, CRM e mapa passam a
ler as views seguras descritas neste diretório.

Abra os dois aplicativos por um servidor local ou publicação HTTP(S), por
exemplo `http://localhost:...`; não abra os arquivos HTML com duplo clique.
Na raiz do projeto, rode `node scripts/servidor-local.js` e use
`http://localhost:8080`.

## 1. Obter as credenciais corretas

No dashboard do **novo projeto Supabase**:

1. Abra `Connect` no topo do dashboard (ou `Settings > API Keys`).
2. Copie a **Project URL**, no formato `https://seu-projeto.supabase.co`.
3. Copie a **Publishable key** (`sb_publishable_...`). Em projetos antigos, a
   chave `anon` também funciona temporariamente.

Nunca use nem envie a chave `secret` ou `service_role`. Elas ignoram as regras
de segurança do banco e pertencem exclusivamente ao backend.

## 2. Preparar o CRM

1. Abra a Central Comercial.
2. Clique no avatar `MA`, no canto superior direito.
3. Selecione `Conectar banco de dados`.
4. Cole a URL e a chave pública.
5. Clique em `Testar conexão`. O resultado esperado é `Projeto acessível`.
6. Clique em `Salvar conexão`.

## 3. Preparar o mapa

1. Abra o aplicativo de mapa.
2. Clique no ícone de banco de dados na barra superior (`Conexão`).
3. Cole a mesma URL e chave pública, teste e salve.

Quando CRM e mapa são abertos no mesmo domínio, a configuração é compartilhada
automaticamente. Se estiverem em domínios, portas ou dispositivos diferentes,
repita o preenchimento em cada um.

## O que um teste aprovado significa

Ele confirma que a URL e a chave pública alcançam a API do projeto. Ele **não**
autoriza leitura de empresas, contatos ou histórico — isso é intencional.

Após o login, a carteira e as viagens passam a ser carregadas do banco
unificado. Sem conexão autenticada, o aplicativo permanece em modo demonstração
local.

## 4. Liberar a leitura da equipe

Uma conexão testada não dá acesso aos dados por si só. Execute no SQL Editor,
nesta ordem:

1. `01_api_leitura_autenticada.sql`;
2. `02_validar_api_leitura.sql`.
3. `03_recarregar_cache_api.sql`.
4. `04_api_escrita_viagens.sql`.
5. `05_equipe_comercial.sql` (depois dos convites da equipe).

Depois abra **Settings > API** no Supabase e inclua somente `api` em
**Exposed schemas**. Não inclua `cadastro`, `mapa` ou `crm`: eles continuam
internos ao banco.

O segundo arquivo deve mostrar, para a primeira carga de carcinicultura,
`12` linhas `CLIENTE` e `865` linhas `LEAD`.

O terceiro arquivo força a Data API a reconhecer as views recém-criadas. Use-o
também se o navegador retornar `404` para uma view que existe no SQL Editor.

O quarto arquivo cria a view `api.vw_viagens` e a função autenticada
`api.criar_viagem`. Ela grava a ficha, participantes e clientes planejados sem
expor acesso direto às tabelas internas do schema `crm`.

## 5. Criar os acessos da equipe

1. Abra **Authentication > Users** no dashboard.
2. Clique em **Add user** e envie um convite para cada endereço:
   - `comercial3@maisintegradora.com.br` — Jefferson Ramires;
   - `comercial2@maisintegradora.com.br` — Bárbara Vieira;
   - `comercial1@maisintegradora.com.br` — Ricardo Castro Alves.
3. Cada pessoa deve concluir o convite e definir a própria senha.
4. Execute novamente `05_equipe_comercial.sql`. Ele vincula os perfis pelo
   e-mail e não cria nem altera senhas.
5. Entre pelo painel de conexão do CRM usando um dos acessos convidados.

Depois da vinculação, a lista de participantes das viagens vem de
`api.vw_equipe`. Se o arquivo ainda não tiver sido executado, o aplicativo
mantém os dados locais de demonstração e a carteira remota continua disponível.

Nesta primeira versão, qualquer usuário criado pela administração pode ler a
carteira e registrar viagens. As demais escritas serão liberadas por função em
etapas próprias.

## Próximas etapas de construção

1. políticas de escrita por função para visitas e despesas;
2. perfis de equipe e trilha de auditoria por usuário;
3. retirada gradual dos fluxos demonstrativos que ainda não têm escrita no banco.

As tabelas continuam protegidas com RLS. A referência oficial é:

- [Chaves de API do Supabase](https://supabase.com/docs/guides/getting-started/api-keys)
- [Schemas personalizados na Data API](https://supabase.com/docs/guides/api/using-custom-schemas)
- [Segurança de dados e RLS](https://supabase.com/docs/guides/database/secure-data)
