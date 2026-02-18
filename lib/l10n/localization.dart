import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

extension BuildContextL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

Locale resolveAppLocale(String? localeTag) {
  if (localeTag == null || localeTag.trim().isEmpty) {
    return const Locale('en');
  }

  final normalized = localeTag.replaceAll('-', '_').trim();
  final parts = normalized.split('_');
  final locale = parts.length > 1
      ? Locale(parts[0], parts[1])
      : Locale(parts[0]);

  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == locale.languageCode &&
        (supported.countryCode ?? '') == (locale.countryCode ?? '')) {
      return supported;
    }
  }

  for (final supported in AppLocalizations.supportedLocales) {
    if (supported.languageCode == locale.languageCode) {
      return supported;
    }
  }

  return const Locale('en');
}

String appLocaleTag(Locale locale) {
  if (locale.countryCode == null || locale.countryCode!.isEmpty) {
    return locale.languageCode;
  }
  return '${locale.languageCode}_${locale.countryCode}';
}

AppLocalizations appLocalizationsForTag(String? localeTag) {
  return lookupAppLocalizations(resolveAppLocale(localeTag));
}
