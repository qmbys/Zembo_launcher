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

## Выпуск новой версии
1. Поменяй `version:` в `pubspec.yaml`, например на `1.0.1+2`.
2. Закоммить и запушь изменения.
3. Создай и запушь тег: `git tag v1.0.1 && git push origin v1.0.1`.
4. GitHub Actions соберёт Windows-версию и опубликует релиз с zip-архивом. Лаунчеры у пользователей увидят обновление.

## Лицензия
MIT
