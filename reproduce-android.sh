#!/usr/bin/env bash
# Builds ReproducerApp for Android, installs it on the device adb is attached to (ANDROID_SERIAL names one of several),
# starts Metro, launches the app and reads what its red box shows. ReproducerApp/metro.config.js has a resolver that
# throws a plain Error for the module App.tsx imports, so Metro answers the app's bundle request with an InternalError,
# which names no file, line or column.
# Exits 1 while the red box shows the raw answer (its "Body:", its JSON escapes or its ANSI escape sequences), 0 once it
# shows the answer's message without them, and 2 when a step fails, Metro answers anything but that InternalError, or
# the red box shows another error.
# React Native logs "Exception in native call" and then posts the red box to the UI thread, and logs nothing once it is
# up: the dump that follows relies on `uiautomator dump` waiting for the screen to settle, and exits 2 when it finds no
# red box.
set -Eeuo pipefail
trap 'echo "failed: $BASH_COMMAND" >&2; exit 2' ERR
cd "$(dirname "$0")/ReproducerApp"
rm -rf tmp
mkdir tmp
package=com.reproducerapp
bundle_request='/index.bundle?platform=android&dev=true&minify=false'
metro=
stop_metro() {
  [ -n "$metro" ] || return 0
  if [ -r "/proc/$metro/winpid" ]; then
    MSYS2_ARG_CONV_EXCL='*' taskkill /T /F /PID "$(< "/proc/$metro/winpid")" > /dev/null 2>&1 || true
  else
    pkill -P "$metro" 2> /dev/null || true
    kill "$metro" 2> /dev/null || true
  fi
  metro=
}
trap stop_metro EXIT
# Names each long step on stderr as it starts, so a run that stops shows where.
step() { printf '$ %s\n' "$*" >&2; }

step yarn install --frozen-lockfile
yarn install --frozen-lockfile
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
step ./gradlew assembleDebug -PreactNativeArchitectures="$abi"
(cd android && ./gradlew --quiet assembleDebug "-PreactNativeArchitectures=$abi")
adb uninstall "$package" > /dev/null 2>&1 || true
step adb install app-debug.apk
timeout 600 adb install android/app/build/outputs/apk/debug/app-debug.apk > /dev/null ||
  { echo 'the install failed or did not finish within 600 s' >&2; exit 2; }
adb reverse tcp:8081 tcp:8081 > /dev/null
step react-native start --port 8081

# Metro's output is read until it says the dev server is ready.
exec {output}< <(node node_modules/react-native/cli.js start --port 8081 2>&1 || true)
metro=$!
line=''
while IFS= read -r -t 300 line <&"$output"; do
  printf '%s\n' "$line" >> tmp/metro.log
  [[ $line != *'Dev server ready'* ]] || break
done
if [[ $line != *'Dev server ready'* ]]; then
  cat tmp/metro.log >&2
  echo 'Metro did not say its dev server was ready' >&2
  exit 2
fi
cat <&"$output" >> tmp/metro.log &
exec {output}<&-

adb logcat -c
step adb shell am start -n "$package/.MainActivity"
adb shell am start -n "$package/.MainActivity" > /dev/null
timeout 300 adb logcat -m 1 -e 'Exception in native call' '*:E' > tmp/logcat.txt ||
  { echo 'the app logged no failure within 300 s' >&2; exit 2; }
adb shell uiautomator dump --windows /sdcard/red-box.xml > /dev/null
adb exec-out cat /sdcard/red-box.xml > tmp/red-box.xml
adb exec-out screencap -p > tmp/red-box.png
adb logcat -d -v tag -m 1 -e 'Could not parse DebugServerException' '*:W' > tmp/logcat-parse.txt
status=$(curl -s --max-time 300 -o tmp/answer.json -w '%{http_code}' "http://localhost:8081$bundle_request" || true)
stop_metro

versions=$(node -p "'react-native ' + require('react-native/package.json').version + ', metro ' + require('metro/package.json').version")
device=$(adb shell getprop ro.product.model | tr -d '\r')
android=$(adb shell getprop ro.build.version.release | tr -d '\r')
echo
echo "$versions, $device on Android $android"
answer_verdict=0
node read-answer.mjs "$bundle_request" "$status" tmp/answer.json || answer_verdict=$?
tr -d '\r' < tmp/logcat-parse.txt | awk '
  { shown = length($0) > 160 ? substr($0, 1, 160) "…" : $0 }
  !through_parse { print shown; if ($0 ~ /DebugServerException[$]Companion[.]parse/) through_parse = 1; next }
  { frames_left_out = 1 }
  END { if (frames_left_out) print "…" }
' > tmp/parse-failure.txt
if [ -s tmp/parse-failure.txt ]; then
  echo "React Native's log as it reads the answer:"
  sed 's/^/  /' tmp/parse-failure.txt
else
  echo 'React Native logged no failure to parse the answer'
fi
verdict=0
node read-red-box.mjs tmp/red-box.xml || verdict=$?
[ "$answer_verdict" = 0 ] || exit 2
exit "$verdict"
