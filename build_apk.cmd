@echo off
REM ============================================================
REM  영어앱 APK 빌드 스크립트
REM  이 파일을 더블클릭하면 Gemini API 키(env.json)를 포함해서
REM  APK를 빌드합니다. 키가 자동으로 들어가므로 AI 기능이 작동합니다.
REM ============================================================

cd /d "%~dp0"

echo.
echo [1/2] 이전 빌드 정리 중...
call flutter clean

echo.
echo [2/2] APK 빌드 중 (Gemini 키 포함)...
call flutter build apk --release --dart-define-from-file=env.json

echo.
if exist "build\app\outputs\flutter-apk\app-release.apk" (
  echo ============================================================
  echo  빌드 완료!
  echo  APK 위치: build\app\outputs\flutter-apk\app-release.apk
  echo ============================================================
) else (
  echo 빌드에 실패했습니다. 위 로그를 확인하세요.
)

echo.
pause
