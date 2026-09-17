import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

typedef ShareBytesFn = Future<void> Function(List<int> bytes, String filename);

/// Writes the bytes to the temp dir and opens the platform share sheet.
Future<void> shareBytes(List<int> bytes, String filename) async {
  final f = File('${(await getTemporaryDirectory()).path}/$filename');
  await f.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(files: [XFile(f.path)]));
}
