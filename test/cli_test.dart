import 'dart:io';

import 'package:flutter_uat/flutter_uat.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<(int, String, String)> run(List<String> args) async {
  final out = StringBuffer(), err = StringBuffer();
  final code = await runCli(args, out: out, err: err);
  return (code, out.toString(), err.toString());
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('flutter_uat_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('version prints the package version', () async {
    final (code, out, _) = await run(['version']);
    expect(code, 0);
    expect(out.trim(), packageVersion);
  });

  test('packageVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':').last.trim(), packageVersion);
  });

  test('no arguments prints usage and exits 2', () async {
    final (code, out, _) = await run([]);
    expect(code, 2);
    expect(out, contains('Usage: flutter_uat'));
  });

  test('bundled scripts resolve', () async {
    final dir = await assetsDirectory();
    for (final f in ['uat.sh', 'flow.py', 'repeat.py', 'sweep.py']) {
      expect(
        File(p.join(dir.path, 'scripts', f)).existsSync(),
        isTrue,
        reason: f,
      );
    }
  });

  test(
    'commands are passed to the bundled scripts and exit codes returned',
    () async {
      // `sweep --list` needs no device: it reads route constants from the source.
      final proj = Directory(p.join(tmp.path, 'proj'))..createSync();
      File(p.join(proj.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      final lib = Directory(p.join(proj.path, 'lib'))..createSync();
      File(
        p.join(lib.path, 'routes.dart'),
      ).writeAsStringSync("const home = '/home';\n");
      expect((await run(['sweep', '--list', '--root', proj.path])).$1, 0);
      // outside any Flutter project: the script's own usage exit code (2)
      final bare = Directory(p.join(tmp.path, 'bare'))..createSync();
      expect((await run(['sweep', '--list', '--root', bare.path])).$1, 2);
    },
  );

  group('install-hooks', () {
    test('refuses outside a Flutter project', () async {
      final prev = Directory.current;
      Directory.current = tmp;
      addTearDown(() => Directory.current = prev);
      final (code, _, err) = await run(['install-hooks']);
      expect(code, 2);
      expect(err, contains('pubspec.yaml'));
    });

    test(
      'writes both hooks, refuses to overwrite, --force overwrites',
      () async {
        File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
        final prev = Directory.current;
        Directory.current = tmp;
        addTearDown(() => Directory.current = prev);
        var r = await run(['install-hooks']);
        expect(r.$1, 0);
        final obs = File(p.join(tmp.path, 'lib/uat/uat_route_observer.dart'));
        final jump = File(p.join(tmp.path, 'lib/uat/uat_jump.dart'));
        expect(obs.existsSync() && jump.existsSync(), isTrue);
        expect(obs.readAsStringSync(), contains('UAT_ROUTES'));
        obs.writeAsStringSync('edited');
        r = await run(['install-hooks']);
        expect(r.$1, 3);
        expect(obs.readAsStringSync(), 'edited');
        r = await run(['install-hooks', '--force']);
        expect(r.$1, 0);
        expect(obs.readAsStringSync(), contains('UAT_ROUTES'));
      },
    );

    test('rejects an unknown argument', () async {
      File(p.join(tmp.path, 'pubspec.yaml')).writeAsStringSync('name: x\n');
      final prev = Directory.current;
      Directory.current = tmp;
      addTearDown(() => Directory.current = prev);
      expect((await run(['install-hooks', '--nope'])).$1, 2);
    });
  });

  test('install-skill copies SKILL.md and CONTRACT.md', () async {
    final dest = p.join(tmp.path, 'skill');
    final r = await run(['install-skill', '--dir', dest]);
    expect(r.$1, 0);
    expect(
      File(p.join(dest, 'SKILL.md')).readAsStringSync(),
      contains('flutter-uat'),
    );
    expect(File(p.join(dest, 'CONTRACT.md')).existsSync(), isTrue);
    expect(File(p.join(dest, 'SLA.md')).existsSync(), isTrue);
  });

  test('shipped text carries no personal paths or app names', () async {
    final root = (await assetsDirectory()).path;
    final bad = RegExp(
      r'/Users/|onyisi|wakajugbe|koins|nugen|tokvault|zapzap',
      caseSensitive: false,
    );
    for (final f in Directory(
      root,
    ).listSync(recursive: true).whereType<File>()) {
      if (f.path.endsWith('.pyc')) continue;
      expect(bad.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
    }
  });

  test('the offline script suite passes', () async {
    final r = await Process.run('bash', ['test/offline/run.sh']);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(r.stdout, contains('failed 0'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
