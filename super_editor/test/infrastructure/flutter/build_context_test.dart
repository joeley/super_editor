import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_editor/src/infrastructure/flutter/build_context.dart';

void main() {
  testWidgets('finds a vertical scrollable beyond a horizontal scrollable', (
    tester,
  ) async {
    final verticalController = ScrollController();
    final horizontalController = ScrollController();
    late BuildContext contentContext;

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          controller: verticalController,
          child: SingleChildScrollView(
            controller: horizontalController,
            scrollDirection: Axis.horizontal,
            child: Builder(
              builder: (context) {
                contentContext = context;
                return const SizedBox(width: 1000, height: 1000);
              },
            ),
          ),
        ),
      ),
    );

    final verticalScrollable =
        contentContext.findAncestorScrollableWithVerticalScroll;

    expect(verticalScrollable?.position, same(verticalController.position));
  });
}
