import 'package:flutter/material.dart';

// ==========================================
// 1. PROJECT MODEL & ENUMS
// ==========================================

class Project {
  final String name;
  final ProjectState state; // Added state field
  final String description;
  final String objective;
  final String location;
  final String organization;
  final String manager;
  final DateTime? startDate;
  final DateTime? endDate;

  Project({
    required this.name,
    this.state = ProjectState.draft,
    this.description = '',
    this.objective = '',
    this.location = '',
    this.organization = '',
    this.manager = '',
    this.startDate,
    this.endDate,
  });
}

enum ProjectState {
  draft('Draft', Colors.grey),
  submitted('Submitted', Colors.lightBlue),
  underReview('Under Review', Colors.orange),
  accepted('Accepted', Colors.blue),
  rejected('Rejected', Colors.red),
  amendmentRequested('Amendment Requested', Colors.amber),
  amending('Amending', Colors.deepOrange),
  preparation('Preparation', Colors.purple),
  active('Active', Colors.green),
  completed('Completed', Colors.teal),
  closed('Closed', Colors.brown);

  // Human-readable label for displaying in UI
  final String label;
  
  // Associated color for UI badges/chips
  final Color color;

  const ProjectState(this.label, this.color);
}

class ReviewAction {
  final ProjectState previousState;
  final ProjectState newState;
  final String comment;
  final String reviewerName;
  final DateTime timestamp;

  ReviewAction({
    required this.previousState,
    required this.newState,
    required this.comment,
    required this.reviewerName,
    required this.timestamp,
  });
}

// ==========================================
// 2. FUNDING MODEL & ENUMS
// ==========================================

enum FundingSourceType {
  grant('Grant', Icons.card_giftcard),
  loan('Loan', Icons.account_balance),
  equity('Equity / Investor', Icons.show_chart),
  internal('Internal Capital', Icons.business);

  final String label;
  final IconData icon;
  const FundingSourceType(this.label, this.icon);
}

class FundingSource {
  final String id;
  final String title;
  final FundingSourceType type;
  final double amount;
  final String providerName;

  FundingSource({
    required this.id,
    required this.title,
    required this.type,
    required this.amount,
    required this.providerName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type.name,
      'amount': amount,
      'providerName': providerName,
    };
  }

  factory FundingSource.fromMap(Map<String, dynamic> map) {
    return FundingSource(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      type: FundingSourceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => FundingSourceType.grant,
      ),
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      providerName: map['providerName'] ?? '',
    );
  }
}

// ==========================================
// 3. BUDGET MODEL & ENUMS
// ==========================================

enum CostCategory {
  labor('Labor / Salaries', Icons.person_outline),
  materials('Materials', Icons.inventory_2_outlined),
  equipment('Equipment Rental', Icons.build_outlined),
  permits('Permits & Legal', Icons.gavel_outlined),
  contingency('Contingency', Icons.shield_outlined);

  final String label;
  final IconData icon;
  const CostCategory(this.label, this.icon);
}

class BudgetItem {
  final String id;
  final String title;
  final CostCategory category;
  final double estimatedCost;
  final double actualCost;

  BudgetItem({
    required this.id,
    required this.title,
    required this.category,
    required this.estimatedCost,
    this.actualCost = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'category': category.name,
      'estimatedCost': estimatedCost,
      'actualCost': actualCost,
    };
  }

  factory BudgetItem.fromMap(Map<String, dynamic> map) {
    return BudgetItem(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      category: CostCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => CostCategory.labor,
      ),
      estimatedCost: (map['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      actualCost: (map['actualCost'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

// ==========================================
// 4. RESPONSIBILITIES (RACI) MODEL & ENUMS
// ==========================================

enum RaciRole {
  responsible('R', 'Responsible', 'Does the work to complete the task.', Colors.blue),
  accountable('A', 'Accountable', 'Final decision-maker and ultimate owner.', Colors.purple),
  consulted('C', 'Consulted', 'Provides vital input and feedback.', Colors.amber),
  informed('I', 'Informed', 'Kept updated on progress.', Colors.grey);

  final String code;
  final String label;
  final String description;
  final Color color;

  const RaciRole(this.code, this.label, this.description, this.color);
}

class ResponsibilityItem {
  final String id;
  final String taskName;
  final String assignee;
  final RaciRole raciRole;

  ResponsibilityItem({
    required this.id,
    required this.taskName,
    required this.assignee,
    required this.raciRole,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'taskName': taskName,
      'assignee': assignee,
      'raciRole': raciRole.name,
    };
  }

  factory ResponsibilityItem.fromMap(Map<String, dynamic> map) {
    return ResponsibilityItem(
      id: map['id'] ?? '',
      taskName: map['taskName'] ?? '',
      assignee: map['assignee'] ?? '',
      raciRole: RaciRole.values.firstWhere(
        (e) => e.name == map['raciRole'],
        orElse: () => RaciRole.responsible,
      ),
    );
  }
}

// ==========================================
// 5. MILESTONES MODEL
// ==========================================

class ProjectMilestone {
  final String id;
  final String title;
  final String deliverable;
  final DateTime targetDate;
  final bool isCriticalPath;

  ProjectMilestone({
    required this.id,
    required this.title,
    required this.deliverable,
    required this.targetDate,
    this.isCriticalPath = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'deliverable': deliverable,
      'targetDate': targetDate.toIso8601String(),
      'isCriticalPath': isCriticalPath,
    };
  }

  factory ProjectMilestone.fromMap(Map<String, dynamic> map) {
    return ProjectMilestone(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      deliverable: map['deliverable'] ?? '',
      targetDate: DateTime.tryParse(map['targetDate'] ?? '') ?? DateTime.now(),
      isCriticalPath: map['isCriticalPath'] ?? false,
    );
  }
}

// ==========================================
// 6. PROCUREMENT MODEL & ENUMS
// ==========================================

enum ProcurementCategory {
  materials('Materials & Supplies', Icons.inventory_2_outlined),
  equipment('Equipment & Tools', Icons.build_outlined),
  services('External Services / Contractors', Icons.handshake_outlined),
  software('Software & Licensing', Icons.computer_outlined);

  final String label;
  final IconData icon;
  const ProcurementCategory(this.label, this.icon);
}

enum ProcurementStatus {
  planned('Planned', Colors.grey),
  sourcing('Sourcing Vendor', Colors.orange),
  ordered('Order Placed', Colors.blue),
  received('Received / Active', Colors.green);

  final String label;
  final Color color;
  const ProcurementStatus(this.label, this.color);
}

class ProcurementItem {
  final String id;
  final String name;
  final ProcurementCategory category;
  final double estimatedCost;
  final ProcurementStatus status;
  final String preferredSupplier;

  ProcurementItem({
    required this.id,
    required this.name,
    required this.category,
    required this.estimatedCost,
    this.status = ProcurementStatus.planned,
    this.preferredSupplier = '',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category.name,
      'estimatedCost': estimatedCost,
      'status': status.name,
      'preferredSupplier': preferredSupplier,
    };
  }

  factory ProcurementItem.fromMap(Map<String, dynamic> map) {
    return ProcurementItem(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      category: ProcurementCategory.values.firstWhere(
        (e) => e.name == map['category'],
        orElse: () => ProcurementCategory.materials,
      ),
      estimatedCost: (map['estimatedCost'] as num?)?.toDouble() ?? 0.0,
      status: ProcurementStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ProcurementStatus.planned,
      ),
      preferredSupplier: map['preferredSupplier'] ?? '',
    );
  }
}

// ==========================================
// 7. MASTER PREPARATION CONTAINER MODEL
// ==========================================

class ProjectPreparationData {
  final Project project;
  final List<FundingSource> fundingSources;
  final List<BudgetItem> budgetItems;
  final List<ResponsibilityItem> responsibilities;
  final List<ProjectMilestone> milestones;
  final List<ProcurementItem> procurementItems;

  ProjectPreparationData({
    required this.project,
    this.fundingSources = const [],
    this.budgetItems = const [],
    this.responsibilities = const [],
    this.milestones = const [],
    this.procurementItems = const [],
  });

  // Financial aggregates
  double get totalFunding => fundingSources.fold(0.0, (sum, item) => sum + item.amount);
  double get totalBudget => budgetItems.fold(0.0, (sum, item) => sum + item.estimatedCost);
  double get totalProcurement => procurementItems.fold(0.0, (sum, item) => sum + item.estimatedCost);
  double get fundingVariance => totalFunding - totalBudget;

  // Readiness progress (0.0 to 1.0)
  double get readinessProgress {
    int total = 5;
    int completed = 0;

    if (fundingSources.isNotEmpty) completed++;
    if (budgetItems.isNotEmpty) completed++;
    if (responsibilities.isNotEmpty) completed++;
    if (milestones.isNotEmpty) completed++;
    if (procurementItems.isNotEmpty) completed++;

    return completed / total;
  }
}