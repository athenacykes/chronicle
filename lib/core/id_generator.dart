import 'package:uuid/uuid.dart';

abstract class IdGenerator {
  String newId();
}

class UuidV7Generator implements IdGenerator {
  UuidV7Generator() : _uuid = const Uuid();

  final Uuid _uuid;

  @override
  String newId() => _uuid.v7();
}
