# Master Monitor 2.0

Monitoramento informado de aplicativos e diagnóstico do Windows, com envio automático ao Supabase e painel de gestor hospedável no GitHub Pages.

## O que está implementado

- Coletor visível para Windows 10/11 com PowerShell 5.1, sem Python ou Node no computador monitorado.
- Aplicativos em primeiro plano, estimativa de inatividade, CPU/RAM/disco, falhas de aplicativos e eventos de reinicialização.
- Upload a cada cinco minutos enquanto o monitor estiver aberto; fila local e nova tentativa nos ciclos seguintes.
- Confirmação em lotes, identificadores estáveis e deduplicação no Postgres.
- Vínculo de máquina por arquivo de uso único, válido por 24 horas, e credencial própria protegida por DPAPI na conta Windows.
- Painel com login de gestor, gráficos, filtros e atualização a cada 60 segundos enquanto visível.
- Última comunicação, última amostra e revogação de novas transmissões de uma máquina.
- Gráficos de desempenho com médias em cinco minutos; resumo preserva médias ponderadas, picos reais e contagem das amostras >=90%.
- Banco com RLS e sem acesso direto para anon/authenticated. A API valida a identidade de gestor ou de máquina.
- Retenção dos dados recebidos de 30 dias, ajustável no banco, com execução diária por pg_cron.

## Situação desta entrega

O código e o pacote de instalação estão preparados. **Projeto Supabase, repositório, hospedagem e conta inicial de gestor precisam ser configurados antes de usar a versão online.** Ter conectado as contas não cria esses recursos automaticamente.

Validados em Linux: API, migração Postgres via PGlite, políticas/permissões, relatórios, painel em Chromium, sintaxe PowerShell e fila offline. **Não foi executado o instalador/coletor em Windows nem validado o envio contra um projeto Supabase real nesta entrega.** Faça um piloto em uma máquina antes de ampliar.

## Estrutura

- `windows/`: instalador, coletor, fila, sincronizador e relatórios locais.
- `web/`: painel online, sem dependências de CDN.
- `supabase/migrations/`: esquema e rotina de retenção.
- `supabase/functions/monitor-api/`: API única com rotas de gestor e de dispositivo.
- `.github/workflows/`: testes, publicação do painel e publicação manual do backend.
- `scripts/authorize-manager.sql`: convite inicial do e-mail de gestor.
- `PUBLICACAO.md`: configuração de produção.
- `TESTES.md`: verificações realizadas e limites.

## Fluxo após publicar

1. No painel, use **Primeiro acesso** com o e-mail autorizado, defina sua senha e confirme o e-mail.
2. Entre e clique em **Cadastrar máquina**. Informe colaborador, setor e rótulo do equipamento.
3. Baixe `vinculo.json`. Ele contém somente um código temporário para aquela máquina; não uma chave administrativa.
4. No computador do colaborador informado, extraia `windows/`, execute `INSTALAR.cmd` na conta Windows dele e selecione esse arquivo.
5. Depois do primeiro envio, a máquina aparece com comunicação recente. Os relatórios seguintes carregam automaticamente.

Cada conta Windows deve ter seu próprio cadastro. Conta compartilhada não identifica quem está presente. Não é necessário deixar um navegador aberto no computador do colaborador; a janela do monitor precisa continuar aberta ou minimizada.

## Comportamento offline e retenção

A fila só remove um lote depois da confirmação do servidor. Falhas de internet, códigos HTTP de erro e respostas incompletas preservam os registros para tentar novamente. O painel mostra a última comunicação real ao servidor, sem afirmar a causa de uma interrupção.

A fila pendente não é apagada automaticamente: pode crescer se a conexão ficar indisponível por muito tempo. A janela mostra o volume observado na última sincronização. Arquivos CSV/HTML locais têm retenção de 30 dias por padrão; a fila é independente. A retenção na nuvem conta **30 dias desde o recebimento**, não a data original da amostra. Isso permite receber filas antigas. Data incorreta/futura no computador pode bloquear um lote e precisa ser corrigida.

O sincronizador dá até 90 segundos para escoar lotes por execução e usa timeout de 20 segundos por requisição. Em quedas longas, pode levar vários ciclos para transmitir tudo. Um desligamento abrupto pode perder os últimos registros ainda não gravados.

## Segurança e limites de interpretação

O programa não coleta sites/URLs, teclas, títulos de documentos, mensagens, senhas ou telas. Mensagens técnicas do Windows podem conter caminhos e identificação da sessão. Uso de aplicativo e inatividade não medem produtividade nem classificam conduta.

Eventos do Windows e consumo de recursos são do computador inteiro. O colaborador identifica o perfil coletor, sem comprovar autoria de uma falha. Eventos 41 e 6008 podem ser o mesmo incidente. Um congelamento completo pode afetar o próprio coletor.

O usuário do perfil pode encerrar o monitor ou alterar os arquivos locais. DPAPI protege a credencial contra outras contas, mas não contra o próprio usuário ou um administrador. O sistema não é uma solução forense inviolável. Revogar impede novos envios; não encerra o programa remoto ou apaga seu histórico.

Não publique HTMLs com dados incorporados, CSV, códigos de vínculo, credenciais ou dados reais no GitHub Pages. Publique apenas o conteúdo gerado de `web/`. A URL pública do painel não torna o banco público: os dados dependem de autenticação e autorização no servidor.

## Desenvolvimento

Node 22 ou superior para testes e build. Não é dependência do instalador Windows.

```sh
npm ci
npm test
node scripts/build.mjs
```

O `dist/` gerado não inclui dados ou segredos. A chave pública é esperada; `service_role` e `sb_secret_*` nunca vão para o navegador ou para o Windows.

Ao substituir o cadastro de um perfil já vinculado, filas pendentes do cadastro anterior são preservadas em `fila-anterior-*` e não são atribuídas ao novo colaborador. A instalação espera o sincronizador em andamento terminar. Uma reinstalação com o mesmo arquivo já vinculado reutiliza a credencial local.
