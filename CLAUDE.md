# app-rclone

## Objetivo
Aplicativo Flutter/Android com interface gráfica para o rclone. Gerencia remotes (cloud storage), navega arquivos, sincroniza em background e suporta OAuth.

## Stack
- **Frontend**: Flutter/Dart (SDK ^3.10.8), Riverpod 2.x (state management)
- **Android nativo**: Kotlin 2.2.20, Gradle 8.14, Android Plugin 8.11.1
- **Integração rclone**: binário Linux ARM64 baixado em runtime + daemon HTTP RPC (porta 5572, 127.0.0.1)
- **Background sync**: WorkManager + ForegroundService

## Comandos
```bash
flutter run              # Roda no emulador/device
flutter build apk        # Gera APK
flutter analyze          # Análise estática
```

## Estrutura principal
```
lib/
├── main.dart                    # Entry point (ProviderScope)
├── app.dart                     # MaterialApp + bottom nav
├── core/
│   ├── rclone/
│   │   ├── rclone_service.dart  # MethodChannel bridge + lifecycle do daemon
│   │   ├── rclone_api.dart      # HTTP client para o daemon RPC
│   │   └── rclone_updater.dart  # Download do binário em runtime
│   └── providers/
│       └── rclone_providers.dart
└── features/
    ├── setup/                   # Tela de download inicial do binário
    ├── dashboard/, remotes/, files/, transfers/, logs/, settings/
```

## Canais MethodChannel (Flutter ↔ Kotlin)
`binary`, `daemon`, `logs`, `OAuth`, `SAF`

## Android — pontos importantes
- Binário rclone fica em `assets/rclone/` mas **não é commitado** (baixado em runtime)
- `jniLibs/arm64-v8a/librclone.so` é o binário bundlado no build
- SAF (Storage Access Framework): `SafWebDavBridge` resolve URI → path para o rclone
- Gradle JVM com heap 8GB (`gradle.properties`) — não reduzir

## Dependências Flutter (pubspec.yaml)
`flutter_riverpod`, `http`, `path_provider`, `permission_handler`, `shared_preferences`, `intl`, `archive`, `url_launcher`

## Tema
Dark mode com neon green `#39FF14` e violet `#AA00FF`

## Regras
- iOS não iniciado — não criar estrutura iOS sem combinação
- O binário rclone não é commitado (`assets/rclone/rclone` está no .gitignore)
- Daemon sempre roda em ForegroundService para sobreviver ao background Android
- WorkManager para sync agendado — não usar isolates Flutter diretamente para isso
