Zembo Launcher - custom toolbar update

Contains the updated lib/ tree, assets/, and pubspec.yaml.

Install:
1. Back up your project.
2. Copy lib/, assets/, and pubspec.yaml into the project root, replacing files when asked.
3. Run: flutter pub get
4. Run: flutter run -d windows

This uses window_manager to hide the native Windows title bar and draw a custom title bar in Flutter. flutter pub get is required so Flutter can register the Windows plugin.
