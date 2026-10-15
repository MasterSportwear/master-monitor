# Publicação — Supabase + GitHub Pages

A configuração inicial é feita uma vez. Depois dela, o gestor usa o painel e instala/vincula os computadores.

## 1. Recursos de destino

Escolha a organização e o projeto Supabase. Para um novo projeto, confirme o custo e a disponibilidade do plano antes de criar. Crie um repositório próprio, sugerido `master-monitor`, sem reutilizar outros sistemas sem planejamento. A conta conectada nesta sessão foi MasterSportwear; não foi definido um repositório de destino.

Projeto configurado: master-monitor (tctiuewlstrnkwayfaru). Painel publicado: https://mastersportwear.github.io/master-monitor/. web/config.js contém somente URL e chave pública do projeto.

## 2. Banco e API

Com o Supabase CLI autenticado, na raiz do projeto:

```sh
supabase link --project-ref ID_DO_PROJETO
supabase db push
supabase functions deploy monitor-api --no-verify-jwt
```

O `verify_jwt=false` é intencional: a função aplica autenticação própria em **todas** as rotas, aceitando JWT validado de gestor ou token específico de dispositivo. A rota `pair` aceita exclusivamente um código de 256 bits, com expiração e consumo atômico de uso único. Não é um endpoint de ingestão aberto.

A função usa `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` fornecidas pelo runtime do Supabase. Não copie a chave administrativa para o HTML ou para o instalador. Opcionalmente defina `MM_ALLOWED_ORIGIN` para a origem do seu painel (ex.: `https://mastersportwear.github.io`); sem isso, o CORS aceita origens, mas a autorização continua exigida por token. CORS não é a barreira de acesso ao banco.

A migração cria tabelas com prefixo mm_ e as funções correspondentes. O job de limpeza NÃO foi ativado: exclusões automáticas exigem autorização explícita. O script opcional foi separado em scripts/retention-pending-approval.sql e não será executado por db push. Não execute em um banco de terceiros sem conferir os objetos existentes.

## 3. Gestor e autenticação

1. Em `scripts/authorize-manager.sql`, substitua o e-mail de exemplo pelo e-mail que terá acesso.
2. Execute o SQL no projeto. Isso autoriza apenas esse e-mail a reivindicar a função de gestor após confirmação no Supabase Auth.
3. Em Authentication > URL Configuration, coloque o endereço final do painel em Site URL e nos Redirect URLs.
4. Mantenha autenticação por e-mail/senha e confirmação de e-mail habilitadas. O primeiro acesso cria a conta do aplicativo, que é separada da conta de administração do Supabase/GitHub.
5. Abra o painel, preencha e-mail e senha com ao menos 12 caracteres e use **Primeiro acesso**. Confirme o e-mail e volte para **Entrar**.
6. Se a conta do aplicativo já existir, entre com a senha dela. Para uma senha esquecida, use as opções administrativas de recuperação no Supabase Auth; não existe formulário de recuperação nesta versão.

O convite inicial expira em sete dias. Reexecute o SQL do convite, se necessário. Cadastro público de autenticação não concede acesso de gestor a outros e-mails. Uma conta sem convite confirmado recebe 403 da API. Não há edição de permissões pelo navegador.

## 4. GitHub Pages

Envie a raiz deste projeto a um repositório de destino. Em Settings > Pages, escolha GitHub Actions como fonte. Defina estas **Variables** em Settings > Secrets and variables > Actions:

- `MM_SUPABASE_URL`: URL do projeto (sem barra final), como `https://SEU_PROJETO.supabase.co`.
- `MM_PUBLISHABLE_KEY`: chave pública publishable (ou anon legada) do projeto.

Execute o workflow **Publicar painel**. Ele gera `dist/` com a configuração pública e publica apenas o painel. O workflow não publica `windows/`, CSV ou relatórios reais.

Se quiser usar o workflow **Publicar backend Supabase**, configure `SUPABASE_PROJECT_ID` como variável e `SUPABASE_ACCESS_TOKEN` / `SUPABASE_DB_PASSWORD` como secrets do GitHub. Essas credenciais são necessárias apenas ao fluxo de manutenção/deploy; não são usadas pelo navegador ou pelas máquinas. A publicação inicial também pode ser feita pelas integrações conectadas, sem gravar tais secrets no repositório.

Não transforme um repositório privado em público automaticamente. A disponibilidade do GitHub Pages para repositórios privados depende do plano da conta. Se for necessário um repositório público, o código não contém dados reais, mas a decisão de visibilidade deve ser explícita.

## 5. Piloto

- Entre no painel com o gestor e confirme que outra conta não autorizada não lê relatórios.
- Cadastre uma máquina piloto e instale na conta Windows do colaborador informado.
- Confira o nome correto no monitor e o primeiro envio após até cinco minutos.
- Alterne entre aplicativos e confira os gráficos, o período e os filtros.
- Interrompa a internet por alguns minutos. Confirme que a fila aumenta e, ao voltar, diminui sem duplicar tempos.
- Feche e reabra o monitor; faça um reinício normal do Windows e confirme o início automático na mesma conta.
- Revogue um cadastro de teste: o servidor deve recusar os envios posteriores. O histórico deve permanecer.
- A limpeza automática da nuvem permanece desativada enquanto não houver aprovação explícita do prazo de exclusão.

Não provoque quedas de energia, tela azul ou travamentos para testar.

## 6. Operação

Envio aproximadamente a cada cinco minutos; painel atualiza a cada 60 segundos quando visível. Isso não é transmissão instantânea. Fora da sessão Windows, ou com o monitor encerrado, não há coleta completa. A consulta cobre até 31 dias; eventos/operação mostram os 1.000 mais recentes por consulta, com aviso de limitação. Os totais de uso não são truncados por esse limite.

Verifique volume de banco, tráfego e limites do seu plano: dados de vários computadores podem exigir ajuste de retenção ou mudança de plano. Não foi prometido custo operacional zero.

Para alterar a retenção da nuvem, use, por exemplo:

```sql
update public.mm_settings set retention_days=30 where singleton;
```

Se a rotina de limpeza for autorizada e ativada, o job apagará definitivamente os registros recebidos antes do prazo. Faça exportações/backups conforme a necessidade. A rotina não remove dados locais ou usuários.

## Referências oficiais

- https://supabase.com/docs/guides/database/postgres/row-level-security
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets
- https://supabase.com/docs/guides/cron/install
- https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site

Ao substituir o cadastro de um perfil já vinculado, filas pendentes do cadastro anterior são preservadas em `fila-anterior-*` e não são atribuídas ao novo colaborador. A instalação espera o sincronizador em andamento terminar. Uma reinstalação com o mesmo arquivo já vinculado reutiliza a credencial local.
