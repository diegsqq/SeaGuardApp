import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sea_guard/l10n/app_localizations.dart';
import 'firebase_options.dart';
import 'providers/language_provider.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/dashboard/weather_ocean_alerts_screen.dart';
import 'screens/notification_page.dart';
import 'Admin/admin_notification_page.dart';
import 'screens/login/login_screen.dart';
import 'screens/login/register_screen.dart';
import 'screens/login/welcome_screen.dart';
import 'Admin/admin_navigation_bar.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

const AndroidNotificationChannel _defaultAndroidChannel = AndroidNotificationChannel(
  'default_channel',
  'General Notifications',
  description: 'Default channel for general notifications.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
const bool _firebasePhoneAuthTesting = bool.fromEnvironment(
  'FIREBASE_PHONE_AUTH_TESTING',
  defaultValue: false,
);

void _handleNotificationNavigation(Map<String, dynamic> data) {
  final nav = navigatorKey.currentState;
  if (nav == null) return;
  final category = (data['category'] ?? data['type'] ?? '').toString().toLowerCase();
  final targetRole = (data['targetRole'] ?? '').toString().toLowerCase();

  if (targetRole.contains('pcg') || targetRole.contains('admin')) {
    nav.push(MaterialPageRoute(builder: (_) => const AdminNotificationPage()));
    return;
  }

  if (category.contains('weather')) {
    nav.push(MaterialPageRoute(builder: (_) => const WeatherOceanAlertsScreen()));
  } else {
    nav.push(MaterialPageRoute(builder: (_) => const NotificationPage()));
  }
}

Future<void> _initPushNotifications() async {
  final messaging = FirebaseMessaging.instance;

  await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
    provisional: false,
  );

  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const initSettings = InitializationSettings(android: androidInit);
  await _localNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          _handleNotificationNavigation(decoded);
        }
      } catch (_) {}
    },
  );

  await _localNotificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_defaultAndroidChannel);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    if (message.data.isNotEmpty) {
      _handleNotificationNavigation(message.data);
    }
  });

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;
    if (notification != null) {
      await _localNotificationsPlugin.show(
        notification.hashCode,
        notification.title ?? 'Notification',
        notification.body ?? '',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _defaultAndroidChannel.id,
            _defaultAndroidChannel.name,
            channelDescription: _defaultAndroidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: android?.smallIcon ?? '@mipmap/ic_launcher',
          ),
        ),
        payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
      );
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } else {
      Firebase.app();
    }
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      Firebase.app();
    } else {
      rethrow;
    }
  }

  // Keep real OTP working in normal debug builds. Enable Firebase phone-auth
  // testing explicitly with --dart-define=FIREBASE_PHONE_AUTH_TESTING=true.
  if (_firebasePhoneAuthTesting && Platform.isAndroid) {
    await FirebaseAuth.instance.setSettings(
      appVerificationDisabledForTesting: true,
      forceRecaptchaFlow: true,
    );
  }

  final prefs = await SharedPreferences.getInstance();
  final savedLangCode = prefs.getString('languageCode') ?? 'en';

  await _initPushNotifications();

  runApp(
    ChangeNotifierProvider(
      create: (_) => LanguageProvider(Locale(savedLangCode)),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = Provider.of<LanguageProvider>(context).locale;

    return MaterialApp(
      title: 'SEAGUARD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: Colors.white,
        textTheme: const TextTheme(
          bodyMedium: TextStyle(fontSize: 16),
        ),
      ),

      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fil'),
      ],
      navigatorKey: navigatorKey,

      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context);
            final textScale = constraints.maxWidth < 360
                ? 0.9
                : constraints.maxWidth < 480
                    ? 0.95
                    : 1.0;

            final wrappedChild = Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: child ?? const SizedBox.shrink(),
              ),
            );

            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: wrappedChild,
            );
          },
        );
      },

      initialRoute: '/',
      routes: {
        '/': (context) => const WelcomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/adminDashboard': (context) => const AdminNavigationScaffold(),
      },
    );
  }
}
