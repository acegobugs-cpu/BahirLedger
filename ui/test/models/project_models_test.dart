import 'package:bahir_ledger/src/models/project_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Project defaults to a draft with optional details unset', () {
    final project = Project(name: 'Test project');
    expect(project.name, 'Test project');
    expect(project.state, ProjectState.draft);
    expect(project.description, isEmpty);
    expect(project.objective, isEmpty);
    expect(project.location, isEmpty);
    expect(project.organization, isEmpty);
    expect(project.manager, isEmpty);
    expect(project.startDate, isNull);
    expect(project.endDate, isNull);
  });

  test('Preparation items preserve constructor defaults', () {
    expect(
      BudgetItem(
        id: 'b',
        title: 'Labor',
        category: CostCategory.labor,
        estimatedCost: 10,
      ).actualCost,
      0,
    );
    expect(
      ProjectMilestone(
        id: 'm',
        title: 'Handover',
        deliverable: 'Report',
        targetDate: DateTime.utc(2027),
      ).isCriticalPath,
      isFalse,
    );
    final item = ProcurementItem(
      id: 'p',
      name: 'Tool',
      category: ProcurementCategory.equipment,
      estimatedCost: 10,
    );
    expect(item.status, ProcurementStatus.planned);
    expect(item.preferredSupplier, isEmpty);
  });

  group('Serialization preserves every field', () {
    for (final type in FundingSourceType.values) {
      test('FundingSource ${type.name}', () {
        final map = <String, dynamic>{
          'id': 'f1',
          'title': 'Seed funding',
          'type': type.name,
          'amount': 1250.5,
          'providerName': 'Provider',
        };
        expect(FundingSource.fromMap(map).toMap(), map);
      });
    }
    for (final category in CostCategory.values) {
      test('BudgetItem ${category.name}', () {
        final map = <String, dynamic>{
          'id': 'b1',
          'title': 'Allocation',
          'category': category.name,
          'estimatedCost': 900.5,
          'actualCost': 200.25,
        };
        expect(BudgetItem.fromMap(map).toMap(), map);
      });
    }
    for (final role in RaciRole.values) {
      test('ResponsibilityItem ${role.name}', () {
        final map = <String, dynamic>{
          'id': 'r1',
          'taskName': 'Inspection',
          'assignee': 'Reviewer',
          'raciRole': role.name,
        };
        expect(ResponsibilityItem.fromMap(map).toMap(), map);
      });
    }
    for (final critical in [false, true]) {
      test('ProjectMilestone critical=$critical', () {
        final date = DateTime.utc(2027, 2, 3, 14, 30);
        final map = <String, dynamic>{
          'id': 'm1',
          'title': 'Handover',
          'deliverable': 'Signed report',
          'targetDate': date.toIso8601String(),
          'isCriticalPath': critical,
        };
        final restored = ProjectMilestone.fromMap(map);
        expect(restored.targetDate, date);
        expect(restored.toMap(), map);
      });
    }
    for (final category in ProcurementCategory.values) {
      for (final status in ProcurementStatus.values) {
        test('ProcurementItem ${category.name}/${status.name}', () {
          final map = <String, dynamic>{
            'id': 'p1',
            'name': 'Purchase',
            'category': category.name,
            'estimatedCost': 40.5,
            'status': status.name,
            'preferredSupplier': 'Supplier',
          };
          expect(ProcurementItem.fromMap(map).toMap(), map);
        });
      }
    }
  });

  group('Preparation aggregate getters', () {
    test('Empty preparation has zero totals and readiness', () {
      final data = ProjectPreparationData(project: Project(name: 'Empty'));
      expect(data.totalFunding, 0);
      expect(data.totalBudget, 0);
      expect(data.totalProcurement, 0);
      expect(data.fundingVariance, 0);
      expect(data.readinessProgress, 0);
    });

    test('Totals are recomputed and readiness counts sections, not items', () {
      final funding = <FundingSource>[];
      final budget = <BudgetItem>[];
      final responsibilities = <ResponsibilityItem>[];
      final milestones = <ProjectMilestone>[];
      final procurement = <ProcurementItem>[];
      final data = ProjectPreparationData(
        project: Project(name: 'Prepared'),
        fundingSources: funding,
        budgetItems: budget,
        responsibilities: responsibilities,
        milestones: milestones,
        procurementItems: procurement,
      );

      funding.addAll([
        FundingSource(
          id: 'f1',
          title: 'Grant',
          type: FundingSourceType.grant,
          amount: 100.25,
          providerName: 'Donor',
        ),
        FundingSource(
          id: 'f2',
          title: 'Internal',
          type: FundingSourceType.internal,
          amount: 50.5,
          providerName: 'Organization',
        ),
      ]);
      expect(data.totalFunding, 150.75);
      expect(data.readinessProgress, 0.2);
      budget.addAll([
        BudgetItem(
          id: 'b1',
          title: 'Labor',
          category: CostCategory.labor,
          estimatedCost: 200,
          actualCost: 999,
        ),
        BudgetItem(
          id: 'b2',
          title: 'Materials',
          category: CostCategory.materials,
          estimatedCost: 20.25,
        ),
      ]);
      expect(data.totalBudget, 220.25);
      expect(data.fundingVariance, -69.5);
      expect(data.readinessProgress, 0.4);
      responsibilities.add(
        ResponsibilityItem(
          id: 'r1',
          taskName: 'Inspect',
          assignee: 'Reviewer',
          raciRole: RaciRole.accountable,
        ),
      );
      expect(data.readinessProgress, 0.6);
      milestones.add(
        ProjectMilestone(
          id: 'm1',
          title: 'Handover',
          deliverable: 'Report',
          targetDate: DateTime.utc(2027),
        ),
      );
      expect(data.readinessProgress, 0.8);
      procurement.addAll([
        ProcurementItem(
          id: 'p1',
          name: 'Tool',
          category: ProcurementCategory.equipment,
          estimatedCost: 30.25,
        ),
        ProcurementItem(
          id: 'p2',
          name: 'Service',
          category: ProcurementCategory.services,
          estimatedCost: 20.5,
        ),
      ]);
      expect(data.totalProcurement, 50.75);
      expect(data.readinessProgress, 1);
      budget.clear();
      expect(data.totalBudget, 0);
      expect(data.fundingVariance, 150.75);
      expect(data.readinessProgress, 0.8);
    });
  });
}
