import 'console.dart';
import 'plain.dart';
import 'skin.dart';

final List<Skin> skins = [plainSkin, consoleSkin];

Skin skinById(String id) => skins.firstWhere((s) => s.id == id, orElse: () => plainSkin);
