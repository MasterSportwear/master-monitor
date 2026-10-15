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
