import 'dart:io';

import 'package:path/path.dart' as p;

import 'assets.dart';

/// The version printed by `flutter_uat version`; kept equal to `pubspec.yaml`
/// (a test enforces it).
const packageVersion = '0.1.4';

const _usage = '''
flutter_uat $packageVersion: drive and verify Flutter apps on Android by label.

Usage: flutter_uat [-s SERIAL] [-p PACKAGE] <command> [args]

Handled here:
  version                         print the version
  where                           print the directory of the bundled scripts
  install-hooks [--dir D] [--force]
                                  copy the optional app-side hooks (route observer,
                                  route jump) into a Flutter project (default D=lib/uat)
  install-skill [--dir D] [--force]
                                  copy the short guide (SKILL.md), REFERENCE.md, CONTRACT.md
                                  and SLA.md for an AI agent
                                  (default D=~/.claude/skills/flutter-uat)
  help                            this text

Everything else goes to the bundled uat.sh: labels, find, taplabel, typein,
waitfor, assert, flow, repeat, sweep, stability, emu, build, doctor ...
Run `flutter_uat doctor` first. Needs bash, adb and python3.''';

/// Runs the CLI and returns the process exit code.
///
/// [out] and [err] default to stdout and stderr.
Future<int> runCli(
  List<String> args, {
  StringSink? out,
  StringSink? err,
}) async {
  final o = out ?? stdout;
  final e = err ?? stderr;
  if (args.isEmpty || args.first == 'help' || args.first == '--help') {
    o.writeln(_usage);
    return args.isEmpty ? 2 : 0;
  }
  // global flags are for uat.sh; the Dart-side commands come first.
  switch (args.first) {
    case 'version' || '--version':
      o.writeln(packageVersion);
      return 0;
    case 'where':
      o.writeln((await assetsDirectory()).path);
      return 0;
    case 'install-hooks':
      return _installHooks(args.skip(1).toList(), o, e);
    case 'install-skill':
      return _installSkill(args.skip(1).toList(), o, e);
  }
  return _passthrough(args, e);
}

Future<int> _passthrough(List<String> args, StringSink err) async {
  final assets = await assetsDirectory();
  final scripts = p.join(assets.path, 'scripts');
  final entry = p.join(scripts, 'uat.sh');
  if (!File(entry).existsSync()) {
    err.writeln('bundled uat.sh not found at $entry');
    return 2;
  }
  // pub archives do not reliably keep the executable bit, and the scripts call
  // each other directly.
  await Process.run('chmod', [
    'u+x',
    ...Directory(scripts).listSync().map((f) => f.path),
  ]);
  final proc = await Process.start(
      'bash',
      [
        entry,
        ...args,
      ],
      mode: ProcessStartMode.inheritStdio);
  return proc.exitCode;
}

({String? dir, bool force, String? bad}) _parse(List<String> args) {
  String? dir;
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--dir' when i + 1 < args.length:
        dir = args[++i];
      case '--force':
        force = true;
      default:
        return (dir: null, force: false, bad: args[i]);
    }
  }
  return (dir: dir, force: force, bad: null);
}

int _copyAll(
  Map<String, String> files,
  Directory dest,
  bool force,
  StringSink out,
  StringSink err,
) {
  final clash =
      files.keys.where((n) => File(p.join(dest.path, n)).existsSync()).toList();
  if (clash.isNotEmpty && !force) {
    err.writeln(
      'refusing to overwrite ${clash.join(', ')} in ${dest.path} '
      '(use --force)',
    );
    return 3;
  }
  dest.createSync(recursive: true);
  files.forEach((name, src) {
    File(src).copySync(p.join(dest.path, name));
    out.writeln('wrote ${p.join(dest.path, name)}');
  });
  return 0;
}

Future<int> _installHooks(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  final a = _parse(args);
  if (a.bad != null) {
    err.writeln('unknown argument: ${a.bad}');
    return 2;
  }
  if (!File('pubspec.yaml').existsSync()) {
    err.writeln('run this from a Flutter project root (no pubspec.yaml here)');
    return 2;
  }
  final snippets = p.join((await assetsDirectory()).path, 'snippets');
  final code = _copyAll(
    {
      'uat_route_observer.dart': p.join(
        snippets,
        'uat_route_observer.dart.txt',
      ),
      'uat_jump.dart': p.join(snippets, 'uat_jump.dart.txt'),
    },
    Directory(a.dir ?? 'lib/uat'),
    a.force,
    out,
    err,
  );
  if (code == 0) {
    out.writeln(
      'Next: add UatRouteObserver() to your router observers, call '
      'UatJump.start(navigatorKey) before runApp, build with '
      '--dart-define=UAT_ROUTES=true. Both are inert without that define.',
    );
  }
  return code;
}

Future<int> _installSkill(
  List<String> args,
  StringSink out,
  StringSink err,
) async {
  final a = _parse(args);
  if (a.bad != null) {
    err.writeln('unknown argument: ${a.bad}');
    return 2;
  }
  final home = Platform.environment['HOME'] ?? '';
  final skill = p.join((await assetsDirectory()).path, 'skill');
  return _copyAll(
    {
      'SKILL.md': p.join(skill, 'SKILL.md'),
      'CONTRACT.md': p.join(skill, 'CONTRACT.md'),
      'SLA.md': p.join(skill, 'SLA.md'),
      'REFERENCE.md': p.join(skill, 'REFERENCE.md'),
    },
    Directory(a.dir ?? p.join(home, '.claude', 'skills', 'flutter-uat')),
    a.force,
    out,
    err,
  );
}
