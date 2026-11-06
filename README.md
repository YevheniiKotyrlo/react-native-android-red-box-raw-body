# React Native's Android red box shows a Metro error answer that names no place as its raw JSON body

When Metro answers a bundle request with an `InternalError` — a 500 whose JSON holds `type`, `errors` and `message`,
and no `filename`, `lineNumber` or `column` — the Android red box shows "The development server returned response error
code: 500", the URL and the raw body, with the message's line breaks as `\n` and its code frame's ANSI escape sequences
as `\u001b[…m`. iOS reads the same answer's `message`
([`RCTJavaScriptLoader.mm`](https://github.com/react/react-native/blob/v0.88.1/packages/react-native/React/Base/RCTJavaScriptLoader.mm#L395-L415)).

`ReproducerApp/metro.config.js` has a resolver that throws a plain `Error`, which Metro has no error kind for, when
`App.tsx` imports `./throws-in-the-resolver`.

## Steps

```sh
cd ReproducerApp
yarn install
yarn android
```

The app opens on the red box with the raw answer.

`reproduce-android.sh` runs the same on the device adb is attached to (`ANDROID_SERIAL` names one of several): it builds
and installs the debug app, starts Metro, launches the app, reads the red box through `uiautomator`, and exits 1 while
it shows the raw answer, 0 once it shows the answer's message without it, and 2 when a step fails or Metro answers
anything but that `InternalError`.
