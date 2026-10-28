@echo off
rem Сборка zembo-guard.jar (нужен JDK 17+). Результат: assets\agent\zembo-guard.jar
cd /d "%~dp0"
if exist out rmdir /s /q out
mkdir out\classes
javac --release 17 -Xlint:all -d out\classes src\dev\zembo\guard\*.java || exit /b 1
(echo Premain-Class: dev.zembo.guard.Agent& echo Can-Retransform-Classes: true& echo Can-Redefine-Classes: true) > out\MANIFEST.MF
jar --create --file out\zembo-guard.jar --manifest out\MANIFEST.MF -C out\classes . || exit /b 1
if not exist ..\..\assets\agent mkdir ..\..\assets\agent
copy /y out\zembo-guard.jar ..\..\assets\agent\zembo-guard.jar
echo Done: assets\agent\zembo-guard.jar
