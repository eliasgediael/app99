# App 99

Lê as ofertas de corrida da 99 pela gravação de tela e fala se a corrida compensa, além de mostrar uma notificação com a mesma frase.

- `App99/`: o app (tela de teste, botão de gravação, atalho "Analisar corrida 99")
- `Broadcast/`: extensão de gravação de tela (ReplayKit)
- `Shared/`: leitor OCR, parser, calculadora, fala e notificação (entram nos dois targets)
- `project.yml`: projeto do XcodeGen (o `.xcodeproj` é gerado no CI)

## Baixar o .ipa

1. No GitHub, abra **Actions** → **Build IPA** → a execução mais recente com ✅. Para gerar um build na hora, use **Run workflow**.
2. Em **Artifacts**, baixe **App99-ipa** (vem em .zip) e extraia o `App99.ipa`.

## Instalar com o Sideloadly (Windows)

1. Instale o iTunes e o iCloud (versões do site da Apple, não as da Microsoft Store) e o [Sideloadly](https://sideloadly.io).
2. Conecte o iPhone no cabo e toque em **Confiar** no aparelho.
3. Arraste o `App99.ipa` pro Sideloadly, informe seu Apple ID e clique em **Start**.
4. No iPhone:
   - **Ajustes → Privacidade e Segurança → Modo de Desenvolvedor**: ative e reinicie.
   - **Ajustes → Geral → VPN e Gerenciamento de Dispositivos**: confie no seu Apple ID.

Com Apple ID gratuito, o app **expira em 7 dias**. Para renovar, instale de novo pelo Sideloadly. O app mais a extensão ocupam 2 dos 3 apps permitidos.

Se o Sideloadly disser que o bundle ID não está disponível, deixe ele trocar o ID. A extensão continua funcionando, mas não aparece mais pré-selecionada: escolha **App 99** manualmente na lista de transmissão.

## Usar

1. Abra o App 99 e permita as notificações.
2. Toque em **Iniciar leitura da tela**, escolha **App 99** e depois **Iniciar Transmissão**. Você ouve "Leitor da 99 ligado".
3. Abra a 99. Cada oferta nova é falada e vira notificação. A mesma oferta não se repete por 20 segundos.
4. Para parar, toque no indicador vermelho de gravação no topo da tela.

Use **Testar com um print** para conferir o OCR num print da galeria. A chave **OCR rápido** usa o mesmo modo da extensão.

Os valores da moto (custo/km, mínimo, bom, alerta de busca) ficam em `Shared/CalculadoraCorrida.swift` (`ConfigMoto`). Mude lá e faça push para gerar um novo .ipa.
