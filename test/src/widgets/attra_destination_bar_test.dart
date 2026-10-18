import 'package:attra/src/theme/app_theme.dart';
import 'package:attra/src/widgets/attra_destination_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pestañas nativas conservan selección y acceso durante scroll',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int selected = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      builder: (BuildContext context, Widget? child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => Scaffold(
          body: ListView.builder(
            itemCount: 30,
            itemBuilder: (BuildContext context, int index) => ListTile(
              title: Text('Respuesta $index'),
            ),
          ),
          bottomNavigationBar: AttraDestinationBar(
            selectedIndex: selected,
            onDestinationSelected: (int index) =>
                setState(() => selected = index),
            destinations: const <NavigationDestination>[
              NavigationDestination(
                  icon: Icon(Icons.explore), label: 'Descubrir'),
              NavigationDestination(
                  icon: Icon(Icons.favorite), label: 'Conexiones'),
              NavigationDestination(icon: Icon(Icons.forum), label: 'Chats'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Perfil'),
            ],
          ),
        ),
      ),
    ));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Chats').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Chats'));
    await tester.pumpAndSettle();
    expect(selected, 2);
    expect(tester.takeException(), isNull);
    if (Theme.of(tester.element(find.byType(AttraDestinationBar))).platform ==
        TargetPlatform.iOS) {
      expect(
          tester
              .widget<CupertinoTabBar>(find.byType(CupertinoTabBar))
              .currentIndex,
          2);
      expect(find.byType(NavigationBar), findsNothing);
    } else {
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2);
      expect(find.byType(CupertinoTabBar), findsNothing);
    }
  },
      variant: const TargetPlatformVariant(
          <TargetPlatform>{TargetPlatform.iOS, TargetPlatform.android}));
}
