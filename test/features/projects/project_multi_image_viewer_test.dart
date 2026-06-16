import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/features/projects/project_image_viewer_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('viewer can page through multiple project images', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProjectImageViewerPage(
          title: '图片资料：行程图（2张）',
          images: [
            ProjectImageViewerItem(path: 'missing-first.png'),
            ProjectImageViewerItem(path: 'missing-second.png'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byTooltip('上一张'), findsOneWidget);
    expect(find.byTooltip('下一张'), findsOneWidget);

    await tester.tap(find.byTooltip('下一张'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('2 / 2'), findsOneWidget);
  });
}
