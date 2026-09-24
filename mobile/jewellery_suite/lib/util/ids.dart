import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A random v4 uuid used as the idempotency key for a locally-created document.
String newUuid() => _uuid.v4();
