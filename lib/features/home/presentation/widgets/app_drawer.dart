import 'package:cerne/core/design_tokens.dart';
import 'package:cerne/core/routing/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A plain [Drawer] widget (not a route) listing "Meus Registros" and
/// "Configurações", each navigating via `context.push` — never disposes
/// Home/Chat's `State` underneath (research.md R3).
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: DesignTokens.colorSurfaceElevated,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: Text('Cerne', style: DesignTokens.textHeadlineMd),
            ),
            const Divider(height: DesignTokens.dividerThickness),
            ListTile(
              title: Text('Meus Registros', style: DesignTokens.textBodyLg),
              onTap: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.records);
              },
            ),
            ListTile(
              title: Text('Configurações', style: DesignTokens.textBodyLg),
              onTap: () {
                Navigator.of(context).pop();
                context.push(AppRoutes.settings);
              },
            ),
          ],
        ),
      ),
    );
  }
}
