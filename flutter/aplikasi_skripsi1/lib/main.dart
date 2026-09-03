import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'page_main.dart';
import 'doorlock_controller.dart';
import 'theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => DoorlockController()..initSystem(),
        ),

        ChangeNotifierProvider(
          create: (_) => ThemeController(),
        ),
      ],

      child: Consumer<ThemeController>(
        builder: (context, theme, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Doorlock App',

            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
            ),

            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
            ),

            themeMode: theme.themeMode,

            home: const MainPage(),
          );
        },
      ),
    );
  }
}