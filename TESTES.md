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
- Deploy e integração com um projeto real do Supabase e GitHub Pages.
- Entrega real de e-mail de confirmação, quotas do projeto e políticas corporativas do Windows.
- Teste de vários expedientes simultâneos ou de volume em produção.

O pacote é uma versão de piloto. A publicação depende da definição dos recursos e da configuração inicial do ambiente, descrita em `PUBLICACAO.md`.
