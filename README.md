# Central Comercial — Demo de Interface

Demonstração multipágina, mobile-first, sem backend e sem Supabase nesta fase.

## O que está implementado

- Dashboard corporativo
- Gestão de clientes e perfis
- Registro rápido de visitas e captação de leads
- Gestão de viagens, participantes, roteiro, anexos, ciclo planejada → em andamento → concluída e atividades
- Financeiro por viagem com comprovantes/anexos
- Usuários, perfis individuais e histórico de atividades
- Relatórios consolidados
- Dados simulados + persistência com `localStorage`
- Captura de foto/vídeo via inputs compatíveis com câmera em dispositivos móveis
- Geolocalização opcional (quando autorizada)
- Marcação manual de localização em mapa simulado
- Skeleton loading, lazy loading, microinterações, estados de feedback e respeito a `prefers-reduced-motion`
- PWA básica com manifest e service worker
- Estrutura pronta para GitHub Pages

## Execução local

A forma mais fiel de testar é servir a pasta com um servidor HTTP local. Com
Node instalado, use o servidor que já vem no projeto:

```bash
node scripts/servidor-local.js
```

Depois acesse:

```text
http://localhost:8080
```

Mapa unificado:

```text
http://localhost:8080/mapa/
```

Ou, se preferir Python:

```bash
python -m http.server 8080
```

Depois acesse:

```text
http://localhost:8080
```

Também é possível usar extensões como Live Server no VS Code.

## GitHub Pages

O projeto inclui `.github/workflows/pages.yml`, configurado para publicar o conteúdo estático da raiz do repositório no GitHub Pages.

No GitHub:

1. Envie todos os arquivos para o repositório.
2. Abra **Settings → Pages**.
3. Em **Build and deployment**, selecione **GitHub Actions**.
4. Faça um push para `main`.

## Persistência local

Os dados ficam em `localStorage`, com a chave:

```text
central_comercial_state_v1
```

Para restaurar os dados iniciais, use o botão **Restaurar demo** no menu do usuário.

## Observação sobre anexos

Arquivos pequenos de imagem (até aproximadamente 700 KB por arquivo) podem ter preview persistido em base64. Arquivos maiores ficam registrados por metadados para evitar estourar o limite do `localStorage`.

## Próxima etapa

Depois da validação da interface e dos fluxos, a estrutura local pode ser usada como referência para modelagem do Supabase:

- autenticação;
- perfis e permissões;
- tabelas e relacionamentos;
- storage;
- regras RLS;
- auditoria;
- sincronização/offline;
- relatórios e consultas.


## Revisão visual V2 - Mais Hidro Soluções

- identidade visual baseada na logomarca fornecida (azul-marinho, ciano e vermelho);
- logomarca em `assets/images/logo-mais.jpg`;
- navegação lateral removida da interface principal e substituída por navegação superior no desktop e barra inferior no mobile;
- cards com maior separação visual, fundos diferenciados, sombras suaves, ícones em marca d'água e indicadores de estado;
- perfil do cliente ampliado com captura rápida de necessidades/interesses;
- carrossel de fotos e vídeos consolidados das visitas;
- relatório PDF individual por visita e PDF consolidado de todas as visitas do cliente;
- PDFs incluem dados da visita, responsável, viagem vinculada, localização, necessidades, anexos e imagens persistidas localmente;
- estados ativos usam pulsos discretos e respeitam `prefers-reduced-motion`.

### Observação sobre mídia local

Nesta etapa sem Supabase, imagens e vídeos pequenos podem ser persistidos em `localStorage`. Arquivos maiores permanecem como metadados para evitar ultrapassar o limite do navegador. A integração posterior com Supabase Storage removerá essa limitação.
