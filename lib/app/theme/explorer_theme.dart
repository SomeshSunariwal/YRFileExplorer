import 'package:flutter/material.dart';

import 'package:yr_file_explorer/core/theme/explorer_style.dart';
import 'package:yr_file_explorer/core/theme/file_categories.dart';

ThemeData buildExplorerTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    primaryColor: primaryBlue,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: primaryBlue,
          brightness: brightness,
          surface: dark ? explorerDarkSurface : Colors.white,
        ).copyWith(
          surfaceContainerLowest: dark ? explorerDarkBase : Colors.white,
          surfaceContainerLow: dark
              ? const Color(0xff303030)
              : const Color(0xfff7f9fb),
          surfaceContainer: dark
              ? explorerDarkSurface
              : const Color(0xfff1f4f7),
          surfaceContainerHigh: dark
              ? const Color(0xff393939)
              : const Color(0xffeaf0f4),
          surfaceContainerHighest: dark
              ? const Color(0xff414141)
              : const Color(0xffe4ebf0),
        ),
    scaffoldBackgroundColor: dark ? explorerDarkBase : explorerCanvas,
    dividerColor: dark ? const Color(0xff494949) : const Color(0xffdce2e8),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: dark ? const Color(0xff2b2b2b) : const Color(0xfff5f8fb),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(
        fontSize: 13,
        color: dark ? const Color(0xffc0c8ce) : const Color(0xff596b7a),
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        color: dark ? const Color(0xffa4afb8) : const Color(0xff748391),
      ),
      floatingLabelStyle: const TextStyle(color: primaryBlue, fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xff4b4b4b) : const Color(0xffdce5ec),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryBlue, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: dark ? const Color(0xff3c3c3c) : const Color(0xffe6ebef),
        ),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: dark ? explorerDarkBase : Colors.white,
      surfaceTintColor: Colors.transparent,
    ),
    appBarTheme: AppBarTheme(
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: dark ? explorerDarkBase : Colors.white,
      foregroundColor: dark ? const Color(0xfff2f2f2) : explorerInk,
      elevation: 0,
      toolbarHeight: 48,
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ExplorerPageTransitions(),
        TargetPlatform.windows: ExplorerPageTransitions(),
      },
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: primaryBlue,
      collapsedIconColor: const Color(0xff8594a7),
      textColor: dark ? Colors.white : explorerInk,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? explorerDarkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? explorerDarkSurface : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 15),
    ),
  );
}
