# Apex

Lê as ofertas de corrida da 99 pela gravação de tela e avisa por notificação (e voz, se ligada) se a corrida compensa. Durante um **turno**, registra ofertas, corridas, tempo, km (GPS) e abastecimentos, e mostra o resumo e o histórico.

- `App99/`: o app (turno, resumo, histórico, linha do tempo, GPS, ajustes, teste com print, atalho "Analisar corrida 99")
- `Broadcast/`: extensão de gravação de tela (ReplayKit): lê a tela e decide o estado das corridas (`MotorCorrida`)
- `Shared/`: leitor OCR, parser, calculadora, notificação, canal de comunicação entre app e extensão
- `project.yml`: projeto do XcodeGen (o `.xcodeproj` é gerado no CI)

## Baixar o .ipa

GitHub → **Actions** → **Build IPA** → execução mais recente com ✅ → **Artifacts** → **App99-ipa-xcode16**. Extraia o `App99.ipa`.

## Instalar (AltStore)

Use o **AltStore**. O Sideloadly quebra a extensão de gravação no iOS 26 (a extensão fecha com erro de assinatura "Invalid Page").

1. No PC: AltServer aberto (ícone de losango perto do relógio), com "Automatically Launch at Startup" marcado.
2. Mande o `App99.ipa` para o iPhone e salve em Arquivos.
3. No iPhone: **AltStore → My Apps → +** → escolha o `App99.ipa`. Atualizações são instaladas por cima, sem apagar os dados.
4. A cada 7 dias o AltStore renova sozinho (AltServer aberto + mesmo Wi-Fi), ou use **My Apps → Refresh All**.

## Usar

1. **Iniciar turno** → escolha **Apex** → **Iniciar Transmissão**. Permita a localização (só é usada durante o turno; aparece a pílula azul).
2. Use a 99 normalmente. Cada oferta vira notificação.
3. **+ Abastecimento** registra valor e preço/L (os litros são calculados).
4. **Encerrar** para a gravação e o GPS e mostra o resumo.

**Regras do faturamento:** só entra corrida **CONFIRMADA** (aceite + passageiro a bordo + tela de fim vistos). Corridas com evidência parcial aparecem como **ESTIMADA**, separadas. O resto é **INDETERMINADA** (R$ 0). A **Linha do tempo** mostra cada decisão e o motivo.

**Configurações:** Mais → Configuração da moto e voz (custo/km, mínimo, nota mínima, voz).
