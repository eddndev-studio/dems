// Selección en compile-time del backend de Drift: ffi (Android/iOS/desktop)
// o wasm (web). Sin esto, `drift/native.dart` arrastra `dart:ffi` al build
// web y dart2js no compila.
export 'unsupported.dart'
    if (dart.library.ffi) 'native.dart'
    if (dart.library.js_interop) 'web.dart';
