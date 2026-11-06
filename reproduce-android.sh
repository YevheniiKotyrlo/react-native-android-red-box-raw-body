#!/usr/bin/env bash
# Builds ReproducerApp for Android, installs it on the device adb is attached to (ANDROID_SERIAL names one of several),
# starts Metro, launches the app and reads what its red box shows. ReproducerApp/metro.config.js has a resolver that
# throws a plain Error for the module App.tsx imports, so Metro answers the app's bundle request with an InternalError,
# which names no file, line or column.
# Exits 1 while the red box shows the raw answer (its "Body:", its JSON escapes or its ANSI escape sequences), 0 once it
# shows the answer's message without them, and 2 when a step fails or the red box shows another error.
set -Eeuo pipefail
trap 'echo "failed: $BASH_COMMAND" >&2; exit 2' ERR
cd "$(dirname "$0")/ReproducerApp"
rm -rf tmp
mkdir tmp
package=com.reproducerapp
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

yarn install --frozen-lockfile
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
(cd android && ./gradlew --quiet assembleDebug "-PreactNativeArchitectures=$abi")
adb uninstall "$package" > /dev/null 2>&1 || true
adb install android/app/build/outputs/apk/debug/app-debug.apk > /dev/null
adb reverse tcp:8081 tcp:8081 > /dev/null

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
adb shell am start -n "$package/.MainActivity" > /dev/null
# React Native logs the failure it shows in the red box, then puts the red box up.
timeout 300 adb logcat -m 1 -s ReactNative:E -e 'Exception in native call' > tmp/logcat.txt ||
  { echo 'the app logged no failure within 300 s' >&2; exit 2; }
adb shell uiautomator dump --windows /sdcard/red-box.xml > /dev/null
adb exec-out cat /sdcard/red-box.xml > tmp/red-box.xml
adb exec-out screencap -p > tmp/red-box.png
status=$(curl -s -o tmp/answer.json -w '%{http_code}' 'http://localhost:8081/index.bundle?platform=android&dev=true&minify=false' || true)
stop_metro

versions=$(node -p "'react-native ' + require('react-native/package.json').version + ', metro ' + require('metro/package.json').version")
device=$(adb shell getprop ro.product.model | tr -d '\r')
android=$(adb shell getprop ro.build.version.release | tr -d '\r')
answer=$(node -e "
const body = JSON.parse(require('node:fs').readFileSync('tmp/answer.json', 'utf8'))
const shown = (value) => (value === undefined ? 'none' : JSON.stringify(value))
console.log('type ' + body.type + ', filename ' + shown(body.filename) + ', lineNumber ' + shown(body.lineNumber) + ', column ' + shown(body.column))
")
echo
echo "$versions, $device on Android $android"
echo "GET /index.bundle?platform=android -> $status: $answer"
verdict=0
node read-red-box.mjs tmp/red-box.xml || verdict=$?
exit "$verdict"
