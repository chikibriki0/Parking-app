package com.example.parking_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity нужен плагину local_auth — BiometricPrompt
// показывается как DialogFragment, для чего активити должна наследоваться
// от FragmentActivity (или её потомка), а не от FlutterActivity.
class MainActivity : FlutterFragmentActivity()
