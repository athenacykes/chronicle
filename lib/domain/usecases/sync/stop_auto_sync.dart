import 'dart:async';

class StopAutoSync {
  const StopAutoSync();

  void call(Timer? timer) {
    timer?.cancel();
  }
}
