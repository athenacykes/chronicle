import 'package:chronicle/l10n/generated/app_localizations.dart';
import 'package:chronicle/presentation/common/shell/chronicle_entity_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';

void main() {
  const appkitUiElementColors = MethodChannel('appkit_ui_element_colors');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, (call) async {
          switch (call.method) {
            case 'getColorComponents':
              return <String, double>{
                'redComponent': 0.0,
                'greenComponent': 0.47843137254901963,
                'blueComponent': 1.0,
                'hueComponent': 0.5866013071895425,
              };
            case 'getColor':
              return 0xFF007AFF;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(appkitUiElementColors, null);
  });

  testWidgets(
    'material matter dialog uses dropdown pickers and ignores backdrop taps',
    (tester) async {
      ChronicleMatterDialogResult? result;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    result = await showChronicleMatterDialog(
                      context: context,
                      mode: ChronicleMatterDialogMode.create,
                    );
                  },
                  child: const Text('Open matter'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open matter'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == 'Title',
        ),
        'Dialog Matter',
      );

      final colorField = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('matter_color_dropdown')),
      );
      colorField.onChanged?.call('#EF4444');
      await tester.pumpAndSettle();

      final iconField = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const Key('matter_icon_dropdown')),
      );
      iconField.onChanged?.call('science');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create').last);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result?.title, 'Dialog Matter');
      expect(result?.color, '#EF4444');
      expect(result?.icon, 'science');
    },
  );

  testWidgets('material category dialog uses dropdown pickers', (tester) async {
    ChronicleCategoryDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showChronicleCategoryDialog(
                    context: context,
                    mode: ChronicleCategoryDialogMode.create,
                  );
                },
                child: const Text('Open category'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open category'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Category name',
      ),
      'Inbox',
    );

    final colorField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('category_color_dropdown')),
    );
    colorField.onChanged?.call('#3B82F6');
    await tester.pumpAndSettle();

    final iconField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const Key('category_icon_dropdown')),
    );
    iconField.onChanged?.call('terminal');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create').last);
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result?.name, 'Inbox');
    expect(result?.color, '#3B82F6');
    expect(result?.icon, 'terminal');
  });

  testWidgets(
    'native matter dialog shows explicit labels and ignores backdrop taps',
    (tester) async {
      await tester.pumpWidget(
        MacosApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Center(
              child: PushButton(
                controlSize: ControlSize.large,
                onPressed: () {
                  showChronicleMatterDialog(
                    context: context,
                    mode: ChronicleMatterDialogMode.create,
                  );
                },
                child: const Text('Open matter'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open matter'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(EditableText).at(0), 'Matter');
      await tester.enterText(find.byType(EditableText).at(1), 'Details');
      await tester.pumpAndSettle();

      final titleLabel = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Title' &&
            widget.style?.fontWeight == FontWeight.w600,
      );
      final descriptionLabel = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data == 'Description' &&
            widget.style?.fontWeight == FontWeight.w600,
      );

      expect(titleLabel, findsOneWidget);
      expect(descriptionLabel, findsOneWidget);
      expect(find.text('Preset colors'), findsOneWidget);
      expect(find.text('Color (hex)'), findsOneWidget);
      expect(find.text('Icon'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('Create Matter'), findsOneWidget);
      expect(titleLabel, findsOneWidget);
    },
  );
}
