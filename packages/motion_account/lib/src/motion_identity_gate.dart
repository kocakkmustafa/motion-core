import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'motion_account_runtime.dart';

/// Keeps every host app's local journal closed while a restored identity is
/// unverified. A real signed-out user may still use the app's guest flow.
class MotionIdentityGate extends StatelessWidget {
  const MotionIdentityGate({
    super.key,
    required this.runtime,
    required this.child,
  });

  final MotionAccountRuntime runtime;
  final Widget child;

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<MotionIdentityPhase>(
    valueListenable: runtime.phase,
    builder: (context, phase, _) {
      if (phase == MotionIdentityPhase.signedOut ||
          phase == MotionIdentityPhase.verified) {
        return child;
      }
      return MaterialApp(
        supportedLocales: const [Locale('tr'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            final tr = Localizations.localeOf(context).languageCode == 'tr';
            return Scaffold(
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (phase == MotionIdentityPhase.verifying) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            tr ? 'Hesap doğrulanıyor…' : 'Checking account…',
                          ),
                        ] else ...[
                          Text(
                            tr
                                ? 'Hesap doğrulanamadı. Bağlantını kontrol edip yeniden dene.'
                                : 'Could not verify your account. Check your connection and retry.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () async {
                              try {
                                await runtime.refreshIdentity();
                              } catch (_) {
                                // The gate remains closed and retry stays available.
                              }
                            },
                            child: Text(tr ? 'Yeniden dene' : 'Retry'),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await runtime.continueAsGuest();
                              } catch (_) {
                                // Keep the identity gate closed on failure.
                              }
                            },
                            child: Text(
                              tr
                                  ? 'Misafir olarak devam et'
                                  : 'Continue as guest',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}
