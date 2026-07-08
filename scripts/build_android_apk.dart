import 'dart:convert';
import 'dart:io';

const _defaultConfigPath = 'config/android_apk_build.local.json';
const _exampleConfigPath = 'config/android_apk_build.example.json';
const _packageName = 'top.schonavi.app';
const _keyPropertiesPath = 'android/key.properties';
const _keyPropertiesExamplePath = 'android/key.properties.example';
const _androidAppDir = 'android/app';
const _targetUniversal = 'universal';
const _targetArmv8 = 'armv8';
const _universalApkPath = 'build/app/outputs/flutter-apk/app-release.apk';
const _armv8ApkPath =
    'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk';

Future<void> main(List<String> args) async {
  try {
    final options = _parseOptions(args);
    if (options.showHelp) {
      stdout.write(_usage);
      return;
    }

    final config = _loadConfig(options.configPath, dryRun: options.dryRun);
    _validateReleaseSigning(dryRun: options.dryRun);
    final command = _buildCommand(config);

    stdout.writeln('Config: ${options.configPath}');
    stdout.writeln('Package: $_packageName');
    stdout.writeln('Target: ${config.target}');
    stdout.writeln('API_BASE_URL: ${config.apiBaseUrl}');
    stdout.writeln('Command: ${_formatCommand(command)}');
    stdout.writeln('Expected APK: ${config.expectedApkPath}');

    if (options.dryRun) {
      stdout.writeln('Dry run: no build executed.');
      return;
    }

    final process = await Process.start(
      command.first,
      command.sublist(1),
      mode: ProcessStartMode.inheritStdio,
      runInShell: Platform.isWindows,
    );
    exitCode = await process.exitCode;
  } on _UsageException catch (error) {
    stderr.writeln(error.message);
    stderr.writeln();
    stderr.write(_usage);
    exitCode = 64;
  } on _ConfigException catch (error) {
    stderr.writeln(error.message);
    exitCode = 78;
  } on FormatException catch (error) {
    stderr.writeln('Invalid JSON config: ${error.message}');
    exitCode = 78;
  }
}

_Options _parseOptions(List<String> args) {
  var configPath = _defaultConfigPath;
  var dryRun = false;
  var showHelp = false;

  for (var i = 0; i < args.length; i += 1) {
    final arg = args[i];
    if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg == '--help' || arg == '-h') {
      showHelp = true;
    } else if (arg == '--config') {
      if (i + 1 >= args.length || args[i + 1].startsWith('--')) {
        throw const _UsageException('Missing value for --config.');
      }
      configPath = args[i + 1];
      i += 1;
    } else if (arg.startsWith('--config=')) {
      configPath = arg.substring('--config='.length);
      if (configPath.isEmpty) {
        throw const _UsageException('Missing value for --config.');
      }
    } else {
      throw _UsageException('Unknown option: $arg');
    }
  }

  return _Options(
    configPath: configPath,
    dryRun: dryRun,
    showHelp: showHelp,
  );
}

_BuildConfig _loadConfig(String path, {required bool dryRun}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw _ConfigException(
      'Config file not found: $path\n'
      'Create one with: Copy-Item $_exampleConfigPath $_defaultConfigPath',
    );
  }

  final root = _asMap(jsonDecode(file.readAsStringSync()), 'root');
  final backend = _asMap(root['backend'], 'backend');
  final apk = _asMap(root['apk'], 'apk');

  final scheme = _stringValue(backend['scheme'], 'backend.scheme')
      .trim()
      .toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    throw const _ConfigException('backend.scheme must be "http" or "https".');
  }

  final host = _stringValue(backend['host'], 'backend.host').trim();
  if (host.isEmpty) {
    throw const _ConfigException('backend.host must not be empty.');
  }
  if (host.contains('://') || host.contains('/')) {
    throw const _ConfigException(
      'backend.host must be a host only, for example "10.0.2.2".',
    );
  }
  if (!dryRun && host == 'YOUR_HOST') {
    throw const _ConfigException(
      'backend.host still uses the example placeholder. '
      'Edit config/android_apk_build.local.json before building.',
    );
  }

  final port = _portValue(backend['port']);

  final target = _stringValue(apk['target'], 'apk.target').trim().toLowerCase();
  if (target != _targetUniversal && target != _targetArmv8) {
    throw const _ConfigException(
      'apk.target must be "universal" or "armv8".',
    );
  }

  return _BuildConfig(
    scheme: scheme,
    host: host,
    port: port,
    target: target,
  );
}

void _validateReleaseSigning({required bool dryRun}) {
  final keyProperties = File(_keyPropertiesPath);
  if (!keyProperties.existsSync()) {
    final message = 'Release signing config not found: $_keyPropertiesPath\n'
        'Create it with: Copy-Item $_keyPropertiesExamplePath $_keyPropertiesPath\n'
        'Then edit $_keyPropertiesPath with your local keystore passwords.';
    if (dryRun) {
      stdout.writeln('Signing: not configured. $message');
      return;
    }
    throw _ConfigException(message);
  }

  final props = _readProperties(keyProperties);
  const requiredKeys = ['storeFile', 'storePassword', 'keyAlias', 'keyPassword'];
  final missing = requiredKeys
      .where((key) => (props[key] ?? '').trim().isEmpty)
      .toList(growable: false);
  if (missing.isNotEmpty) {
    throw _ConfigException(
      'Release signing config is incomplete: $_keyPropertiesPath\n'
      'Missing keys: ${missing.join(', ')}',
    );
  }

  final storeFile = _resolveStoreFile(props['storeFile']!.trim());
  if (!storeFile.existsSync()) {
    final message = 'Release keystore not found: ${storeFile.path}\n'
        'Generate it with keytool, then rebuild.';
    if (dryRun) {
      stdout.writeln('Signing: keystore missing. $message');
      return;
    }
    throw _ConfigException(message);
  }
}

Map<String, String> _readProperties(File file) {
  final result = <String, String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final index = line.indexOf('=');
    if (index <= 0) continue;
    result[line.substring(0, index).trim()] = line.substring(index + 1).trim();
  }
  return result;
}

File _resolveStoreFile(String storeFile) {
  final normalized = storeFile.replaceAll('\\', '/');
  final isAbsolute =
      normalized.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  if (isAbsolute) return File(storeFile);
  return File('$_androidAppDir/$storeFile');
}

List<String> _buildCommand(_BuildConfig config) {
  return <String>[
    'flutter',
    'build',
    'apk',
    '--release',
    if (config.target == _targetArmv8) ...<String>[
      '--split-per-abi',
      '--target-platform',
      'android-arm64',
    ],
    '--dart-define=API_BASE_URL=${config.apiBaseUrl}',
  ];
}

Map<String, Object?> _asMap(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  throw _ConfigException('$name must be an object.');
}

String _stringValue(Object? value, String name) {
  if (value is String) return value;
  throw _ConfigException('$name must be a string.');
}

int _portValue(Object? value) {
  final port = switch (value) {
    int() => value,
    String() => int.tryParse(value),
    _ => null,
  };
  if (port == null || port < 1 || port > 65535) {
    throw const _ConfigException(
      'backend.port must be an integer between 1 and 65535.',
    );
  }
  return port;
}

String _formatCommand(List<String> command) {
  return command.map(_quoteIfNeeded).join(' ');
}

String _quoteIfNeeded(String value) {
  if (value.isEmpty || RegExp(r'\s').hasMatch(value)) {
    return '"${value.replaceAll('"', r'\"')}"';
  }
  return value;
}

const _usage = '''
Usage:
  dart run scripts/build_android_apk.dart [--config <path>] [--dry-run]

Options:
  --config <path>  Build config path. Defaults to $_defaultConfigPath.
  --dry-run        Print the Flutter command without running it.
  -h, --help       Show this help.

Config example:
  $_exampleConfigPath
''';

class _Options {
  const _Options({
    required this.configPath,
    required this.dryRun,
    required this.showHelp,
  });

  final String configPath;
  final bool dryRun;
  final bool showHelp;
}

class _BuildConfig {
  const _BuildConfig({
    required this.scheme,
    required this.host,
    required this.port,
    required this.target,
  });

  final String scheme;
  final String host;
  final int port;
  final String target;

  String get apiBaseUrl => '$scheme://$host:$port';

  String get expectedApkPath =>
      target == _targetUniversal ? _universalApkPath : _armv8ApkPath;
}

class _UsageException implements Exception {
  const _UsageException(this.message);

  final String message;
}

class _ConfigException implements Exception {
  const _ConfigException(this.message);

  final String message;
}
