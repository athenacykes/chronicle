String formatIsoUtc(DateTime value) => value.toUtc().toIso8601String();

DateTime parseIsoUtc(String value) => DateTime.parse(value).toUtc();
