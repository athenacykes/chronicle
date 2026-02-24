import 'package:flutter_riverpod/flutter_riverpod.dart';

class ValueNotifierController<T> extends Notifier<T> {
  ValueNotifierController(this._initialValue);

  final T _initialValue;

  @override
  T build() => _initialValue;

  void set(T value) {
    state = value;
  }
}
