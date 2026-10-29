import 'package:flutter/material.dart';

/// Navegação de seções em linha rolável, na base da AppBar.
///
/// Em tablets estreitos, as seções deixam de disputar espaço com o logo e com o
/// indicador de conexão: elas rolam na própria linha, sempre inteiras.
class SectionNavigation extends StatelessWidget implements PreferredSizeWidget {
  const SectionNavigation({super.key, required this.child});

  final Widget child;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: preferredSize.height,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: child,
      ),
    );
  }
}
