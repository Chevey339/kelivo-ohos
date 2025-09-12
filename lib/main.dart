import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'features/home/pages/home_page.dart';
import 'package:flutter/services.dart';
// Theme is now managed in SettingsProvider
import 'theme/theme_factory.dart';
import 'theme/palettes.dart';
import 'package:provider/provider.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/mcp_provider.dart';
import 'core/providers/tts_provider.dart';
import 'core/providers/assistant_provider.dart';
import 'core/providers/update_provider.dart';
import 'core/services/chat/chat_service.dart';
import 'core/services/mcp/mcp_tool_service.dart';
import 'utils/sandbox_path_resolver.dart';

final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();
bool _didCheckUpdates = false; // one-time update check flag
bool _didEnsureAssistants = false; // ensure defaults after l10n ready


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cache current Documents directory to fix sandboxed absolute paths on iOS
  await SandboxPathResolver.init();
  // Enable edge-to-edge to allow content under system bars (Android)
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => McpToolService()),
        ChangeNotifierProvider(create: (_) => McpProvider()),
        ChangeNotifierProvider(create: (_) => AssistantProvider()),
        ChangeNotifierProvider(create: (_) => TtsProvider()),
        ChangeNotifierProvider(create: (_) => UpdateProvider()),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          // One-time app update check after first build
          if (settings.showAppUpdates && !_didCheckUpdates) {
            _didCheckUpdates = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              try { context.read<UpdateProvider>().checkForUpdates(); } catch (_) {}
            });
          }
          final palette = ThemePalettes.byId(settings.themePaletteId);

          final light = buildLightThemeForScheme(palette.light);
          final dark = buildDarkThemeForScheme(palette.dark);
          
          return MaterialApp(
                debugShowCheckedModeBanner: false,
                title: 'Kelivo',
                // App UI language; null = follow system (respects iOS per-app language)
                locale: settings.appLocaleForMaterialApp,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                theme: light,
                darkTheme: dark,
                themeMode: settings.themeMode,
                navigatorObservers: <NavigatorObserver>[routeObserver],
                home: const HomePage(),
                builder: (ctx, child) {
                  final bright = Theme.of(ctx).brightness;
                  final overlay = bright == Brightness.dark
                      ? const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.light,
                          statusBarBrightness: Brightness.dark,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.light,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        )
                      : const SystemUiOverlayStyle(
                          statusBarColor: Colors.transparent,
                          statusBarIconBrightness: Brightness.dark,
                          statusBarBrightness: Brightness.light,
                          systemNavigationBarColor: Colors.transparent,
                          systemNavigationBarIconBrightness: Brightness.dark,
                          systemNavigationBarDividerColor: Colors.transparent,
                          systemNavigationBarContrastEnforced: false,
                        );
              // Ensure localized defaults (assistants and chat default title) after first frame
              if (!_didEnsureAssistants) {
                _didEnsureAssistants = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  try { ctx.read<AssistantProvider>().ensureDefaults(ctx); } catch (_) {}
                  try { ctx.read<ChatService>().setDefaultConversationTitle(AppLocalizations.of(ctx)!.chatServiceDefaultConversationTitle); } catch (_) {}
                  try { ctx.read<UserProvider>().setDefaultNameIfUnset(AppLocalizations.of(ctx)!.userProviderDefaultUserName); } catch (_) {}
                });
              }

                  return AnnotatedRegion<SystemUiOverlayStyle>(
                    value: overlay,
                    child: child ?? const SizedBox.shrink(),
                  );
                },
              );
        },
      ),
    );
  }
}
 
