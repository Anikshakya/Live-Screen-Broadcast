import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with Firebase.initializeApp.
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDckjbHeDuB2vNNaCJfeL384XKd2bp9mvo',
    appId: '1:924997254704:web:3fbe520a8c464a3d4a77f5',
    messagingSenderId: '924997254704',
    projectId: 'screen-mirror-e6dc0',
    authDomain: 'screen-mirror-e6dc0.firebaseapp.com',
    storageBucket: 'screen-mirror-e6dc0.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAteSNZIsc17eM6XOnr5OvWFgCi-tImMxs',
    appId: '1:924997254704:android:0d4fab5b8140b23d4a77f5',
    messagingSenderId: '924997254704',
    projectId: 'screen-mirror-e6dc0',
    storageBucket: 'screen-mirror-e6dc0.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDJY6D2pHsLQ2lpuKTHMYWKw2MoFQziG2E',
    appId: '1:924997254704:ios:f9b19286f16ed1c64a77f5',
    messagingSenderId: '924997254704',
    projectId: 'screen-mirror-e6dc0',
    storageBucket: 'screen-mirror-e6dc0.firebasestorage.app',
    iosBundleId: 'com.aniklinkin.screenmirror',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDJY6D2pHsLQ2lpuKTHMYWKw2MoFQziG2E',
    appId: '1:924997254704:ios:f9b19286f16ed1c64a77f5',
    messagingSenderId: '924997254704',
    projectId: 'screen-mirror-e6dc0',
    storageBucket: 'screen-mirror-e6dc0.firebasestorage.app',
    iosBundleId: 'com.aniklinkin.screenmirror',
  );
}
