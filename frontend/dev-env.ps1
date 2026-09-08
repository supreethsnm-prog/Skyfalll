# Dot-source this before any flutter/dart/adb/emulator/gradle command:
#   . .\frontend\dev-env.ps1
# Sets up PATH and the JDK Flutter's Android toolchain needs. Without this,
# a fresh PowerShell/Bash session on this machine does not have flutter,
# adb, emulator, sdkmanager, or a JDK 17+ on PATH.

$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_SDK_ROOT = "C:\Users\ACER\AppData\Local\Android\Sdk"
$env:ANDROID_HOME = "C:\Users\ACER\AppData\Local\Android\Sdk"
$env:Path = "$env:JAVA_HOME\bin;C:\src\flutter\bin;$env:ANDROID_SDK_ROOT\platform-tools;$env:ANDROID_SDK_ROOT\emulator;$env:ANDROID_SDK_ROOT\cmdline-tools\latest\bin;" + $env:Path
