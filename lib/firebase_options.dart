import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBpiHFhIYPj6r5chKtjC0MQp440QM6WJOo',
    appId: '1:520008211704:web:5b7eb91ec62a424b16af0d',
    messagingSenderId: '520008211704',
    projectId: 'seaguardproject2025',
    authDomain: 'seaguardproject2025.firebaseapp.com',
    databaseURL: 'https://seaguardproject2025-default-rtdb.firebaseio.com',
    storageBucket: 'seaguardproject2025.firebasestorage.app',
    measurementId: 'G-1CR8YNBLED',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD528CYeRAFOS5qD-6uQPQoAdVj4NBbbSw',
    appId: '1:520008211704:android:020fd6903844b34e16af0d',
    messagingSenderId: '520008211704',
    projectId: 'seaguardproject2025',
    databaseURL: 'https://seaguardproject2025-default-rtdb.firebaseio.com',
    storageBucket: 'seaguardproject2025.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBH3mUqFk7vMDfQH7CUl0jrBF9Io79L8gA',
    appId: '1:520008211704:ios:68327773490d2a9316af0d',
    messagingSenderId: '520008211704',
    projectId: 'seaguardproject2025',
    databaseURL: 'https://seaguardproject2025-default-rtdb.firebaseio.com',
    storageBucket: 'seaguardproject2025.firebasestorage.app',
    androidClientId: '520008211704-s9a8jggkv6lvpoflqbf8ntej0rvkl1qh.apps.googleusercontent.com',
    iosClientId: '520008211704-i6gp1q9mtbbc63ldn274pfsaptc92ta9.apps.googleusercontent.com',
    iosBundleId: 'com.example.seaGuard',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBH3mUqFk7vMDfQH7CUl0jrBF9Io79L8gA',
    appId: '1:520008211704:ios:68327773490d2a9316af0d',
    messagingSenderId: '520008211704',
    projectId: 'seaguardproject2025',
    databaseURL: 'https://seaguardproject2025-default-rtdb.firebaseio.com',
    storageBucket: 'seaguardproject2025.firebasestorage.app',
    androidClientId: '520008211704-s9a8jggkv6lvpoflqbf8ntej0rvkl1qh.apps.googleusercontent.com',
    iosClientId: '520008211704-i6gp1q9mtbbc63ldn274pfsaptc92ta9.apps.googleusercontent.com',
    iosBundleId: 'com.example.seaGuard',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBpiHFhIYPj6r5chKtjC0MQp440QM6WJOo',
    appId: '1:520008211704:web:977a0ddcf92f9f1816af0d',
    messagingSenderId: '520008211704',
    projectId: 'seaguardproject2025',
    authDomain: 'seaguardproject2025.firebaseapp.com',
    databaseURL: 'https://seaguardproject2025-default-rtdb.firebaseio.com',
    storageBucket: 'seaguardproject2025.firebasestorage.app',
    measurementId: 'G-PZ00MYMVLK',
  );

}