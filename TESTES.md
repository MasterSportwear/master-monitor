# Validação da versão 2.0

## Executados

- Análise sintática dos seis scripts Windows em PowerShell 7.4.6, escritos para PowerShell 5.1.
- Fila offline: limites de bytes para mensagens Unicode longas e 507 registros com Unicode, rotação protegida por mutex, lotes de 250, confirmação parcial, reenvio mantendo UUID e remoção somente após confirmação.
- API em Node: primeiro acesso exige convite e e-mail confirmado; tokens, hash SHA-256, normalização dos campos, rejeição de estados/valores/horários inválidos, tamanho máximo, autenticação, permissão de gestor, isolamento entre dispositivos e rejeição de dispositivo revogado.
- Postgres via PGlite: migração executada, vínculo de uso único, deduplicação por chave primária, revogação, agregação de relatório, valores ausentes e zero, RLS/permissões e retenção.
- Chromium: nenhum carregamento de dados antes do login, falha de login, login bem-sucedido, carregamento automático, gráficos e filtros, cadastro, download de vínculo, revogação, limpeza dos dados na saída e layout móvel.
- Build e integridade do ZIP de entrega.

Os dados usados nos testes são fictícios e ficam somente em `tests/`. O build público não incorpora fixtures ou credenciais.

## Ainda não executados

- Instalação, DPAPI, atalhos COM, Win32/CIM e logs em uma máquina Windows real.
- Transmissão de registros por um coletor instalado no Windows real.
- Entrega real de e-mail de confirmação, quotas do projeto e políticas corporativas do Windows.
- Teste de vários expedientes simultâneos ou de volume em produção.

O coletor é uma versão de piloto. Banco, API e painel foram implantados; a criação da senha do gestor e a configuração do redirecionamento de confirmação permanecem como etapas iniciais do usuário.

Implantação: esquema aplicado no Supabase e API monitor-api ativa. Job de exclusão automática não aplicado (pendente de autorização). Painel GitHub Pages publicado.

Testes ao vivo: API /devices sem login 401; /pair com código inexistente 401; /ingest com credencial inexistente 401; acesso anônimo a mm_records negado (permission denied); Auth Settings confirmou e-mail habilitado e confirmação obrigatória. Não foram criados usuários ou máquinas fictícios no projeto real.

## Domínios Chrome 2.1

- Testes de hostname: URLs completas, parâmetros, títulos e conteúdos não passam para os registros.
- Ativação explícita da extensão, mudança de foco, páginas internas e modo anônimo.
- Protocolo Native Messaging: binário com enquadramento de 32 bits, origem permitida, snapshot atômico e limpeza ao desconectar. Testado em Linux (.NET) e no Windows do GitHub (PowerShell 5.1 e executável compilado).
- Leitor: snapshot recente e foco único; rejeição de amostras com mais de 20 segundos, foco ausente, hostname inválido e múltiplos perfis ambíguos.
- API e Postgres: validação, identidade derivada da credencial da máquina, agrupamento por dia/domínio/máquina; RLS preservada.
- Dashboard e HTML diário local: gráfico/tabela de domínios, filtros e limpeza no logout; tempos de aplicativos não são duplicados.
- Fila: rotação, reenvio idempotente, confirmação parcial e limite de bytes, também no Windows CI.
- Ainda requer piloto no Chrome real do usuário: instalação da extensão, descoberta do host pelo Chrome, troca de abas e conferência do domínio na janela e no painel após sincronização. Não foram simulados travamentos do Windows.
