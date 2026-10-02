import 'package:bahir_ledger/main.dart';
import 'package:bahir_ledger/src/data/projects.dart';
import 'package:bahir_ledger/src/models/project_models.dart';
import 'package:bahir_ledger/src/pages/projects/add.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The app aliases this mutable fixture. Restore it even if a test fails;
  // replacing production state ownership belongs to Step 02.
  late List<Project> originalProjects;

  setUp(() {
    originalProjects = List<Project>.of(sampleProjects);
  });

  tearDown(() {
    sampleProjects
      ..clear()
      ..addAll(originalProjects);
  });

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Shell()));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Add Project'));
    await tester.pumpAndSettle();
    expect(find.byType(AddProjectPage), findsOneWidget);
    expect(find.text('New Project'), findsOneWidget);
  }

  testWidgets('Shell displays the project list and add action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Shell()));
    await tester.pumpAndSettle();
    expect(find.text('Project Manager'), findsOneWidget);
    expect(find.text('Active Projects'), findsOneWidget);
    expect(find.text(sampleProjects.first.name), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Add Project'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Opening and canceling a populated form creates nothing', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Canceled draft');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(AddProjectPage), findsNothing);
    expect(find.text('Active Projects'), findsOneWidget);
    expect(sampleProjects, orderedEquals(originalProjects));
    expect(find.text('Canceled draft'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Creating a valid draft adds a visible project row', (
    tester,
  ) async {
    await openForm(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      '  Baseline draft  ',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Baseline description',
    );
    // Finish the text field's automatic scroll before scrolling to submit.
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, 'Create Project'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Project'));
    await tester.pumpAndSettle();
    expect(find.byType(AddProjectPage), findsNothing);
    expect(sampleProjects, hasLength(originalProjects.length + 1));
    expect(sampleProjects.last.name, 'Baseline draft');
    expect(sampleProjects.last.description, 'Baseline description');
    expect(sampleProjects.last.state, ProjectState.draft);
    await tester.scrollUntilVisible(find.text('Baseline draft'), 400);
    final row = find.widgetWithText(ListTile, 'Baseline draft');
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('Draft')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Empty project name is rejected without adding a project', (
    tester,
  ) async {
    await openForm(tester);
    // Exercise the alternate submit action in the app bar.
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();
    expect(find.text('Please enter a name'), findsOneWidget);
    expect(find.byType(AddProjectPage), findsOneWidget);
    expect(sampleProjects, orderedEquals(originalProjects));
    expect(tester.takeException(), isNull);
  });
}
