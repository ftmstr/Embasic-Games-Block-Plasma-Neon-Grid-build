import 'dart:io';

import 'package:flutter/services.dart';

import 'game_repository.dart';
import 'local_game_repository.dart';

/// Only Android's private app files directory is requested. No storage
/// permission, cloud account, tracking service or third-party plugin.
class AppGameStorage {
  static const _channel = MethodChannel(
    'com.embasicgames.block_plasma_neon_grid/storage',
  );

  static Future<GameRepository?> open() async {
    try {
      final path = await _channel.invokeMethod<String>('appFilesDir');
      if (path == null || path.isEmpty) return null;
      return FileGameRepository(Directory(path));
    } on MissingPluginException {
      return null; // Widget tests and platforms without Android channel.
    } on PlatformException {
      return null; // Continue playing if storage cannot be acquired.
    }
  }
}
