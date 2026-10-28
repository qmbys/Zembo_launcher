# Zembo Launcher

Лаунчер Minecraft на Flutter (Windows): сборки с Fabric/Forge, магазин модов, вход через Ely.by, настройки модов и защитный Java-агент.

## Установка
Скачай последний `Zembo_launcher-windows-vX.Y.Z.zip` со страницы [Releases](https://github.com/qmbys/Zembo_launcher/releases), распакуй и запусти `zembo_launcher.exe`. Установщик предложит папку: в ней будет создана `LauncherFiles`.

## Обновления
При запуске лаунчер проверяет последний релиз на GitHub. Если вышла новая версия, на главном экране появляется кнопка «Обновить лаунчер до последней версии?». Файлы Minecraft и сборки при обновлении не затрагиваются.

## Сборка из исходников
```
flutter pub get
flutter run -d windows
```
Защитный агент (`tools/zembo-guard`) пересобирается скриптом `build.bat` / `build.sh` (нужен JDK 17+), результат кладётся в `assets/agent/zembo-guard.jar`.


## Лицензия
MIT
