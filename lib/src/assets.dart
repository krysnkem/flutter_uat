import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

/// Directory holding the bundled scripts, snippets and skill docs.
///
/// `FLUTTER_UAT_ASSETS` overrides it (tests, local development).
Future<Directory> assetsDirectory() async {
  final override = Platform.environment['FLUTTER_UAT_ASSETS'];
  if (override != null && override.isNotEmpty) return Directory(override);
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:flutter_uat/src/assets/scripts/uat.sh'),
  );
  if (uri == null) {
    throw StateError(
      'cannot resolve package:flutter_uat assets; '
      'set FLUTTER_UAT_ASSETS to the assets directory',
    );
  }
  return Directory(p.dirname(p.dirname(uri.toFilePath())));
}
