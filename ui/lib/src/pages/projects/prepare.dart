import 'package:flutter/material.dart';

import '../../models/project_models.dart';

// Preparation status item state model
class ReadinessItem {
  final String title;
  final String subtitle;
  final IconData icon;
  bool isConfigured;

  ReadinessItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.isConfigured = false,
  });
}

class ProjectPreparationPage extends StatefulWidget {
  final Project project;

  const ProjectPreparationPage({super.key, required this.project});

  @override
  State<ProjectPreparationPage> createState() => _ProjectPreparationPageState();
}

class _ProjectPreparationPageState extends State<ProjectPreparationPage> {
  // Readiness Checklist Items
  late final List<ReadinessItem> _readinessItems;

  @override
  void initState() {
    super.initState();
    _readinessItems = [
      ReadinessItem(
        title: 'Funding',
        subtitle: 'Grants, loans, and donor funding sources',
        icon: Icons.account_balance,
        isConfigured: false,
      ),
      ReadinessItem(
        title: 'Budget',
        subtitle: 'Line-item breakdown and cost caps',
        icon: Icons.attach_money,
        isConfigured: false,
      ),
      ReadinessItem(
        title: 'Team',
        subtitle: 'Assigned staff and external contacts',
        icon: Icons.groups,
        isConfigured: true,
      ),
      ReadinessItem(
        title: 'Responsibilities',
        subtitle: 'RACI matrix and role assignments',
        icon: Icons.assignment_ind,
        isConfigured: false,
      ),
      ReadinessItem(
        title: 'Milestones',
        subtitle: 'Key deliverables and target dates',
        icon: Icons.flag,
        isConfigured: false,
      ),
      ReadinessItem(
        title: 'Procurement',
        subtitle: 'Equipment sourcing and vendor contracts',
        icon: Icons.shopping_cart,
        isConfigured: false,
      ),
      ReadinessItem(
        title: 'Required Documents',
        subtitle: 'Permits, environmental clearance, compliance forms',
        icon: Icons.folder_special,
        isConfigured: true,
      ),
    ];
  }

  // Calculate overall readiness progress percentage
  double get _readinessProgress {
    final completed = _readinessItems.where((item) => item.isConfigured).length;
    return completed / _readinessItems.length;
  }

  bool get _isFullyReady => _readinessProgress == 1.0;

  void _configureItem(ReadinessItem item) {
    // Open dynamic configuration bottom sheet
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: 24,
            left: 24,
            right: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(item.icon, color: const Color(0xFF005B7F), size: 28),
                  const SizedBox(width: 12),
                  Text(
                    'Configure ${item.title}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.subtitle,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // Placeholder configuration toggle/action
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Mark ${item.title} as complete'),
                    Switch(
                      value: item.isConfigured,
                      activeColor: Colors.green,
                      onChanged: (val) {
                        setState(() {
                          item.isConfigured = val;
                        });
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _activateProject() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Activate Project'),
          content: Text(
            'Are you sure you want to activate "${widget.project.name}"? '
            'This will transition the status to Active and notify all assigned team members.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(context); // Close dialog
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${widget.project.name} is now ACTIVE!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Confirm Activation'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final configuredCount = _readinessItems.where((i) => i.isConfigured).length;
    final totalCount = _readinessItems.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Preparation Workspace'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Summary Card
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PROJECT PREPARATION',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF70B4C8),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.project.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Readiness Progress Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Readiness: $configuredCount of $totalCount items',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${(_readinessProgress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _readinessProgress,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isFullyReady ? Colors.greenAccent : const Color(0xFF70B4C8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Readiness Checklist',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Readiness List Items
          ..._readinessItems.map((item) {
            return Card(
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              child: ListTile(
                onTap: () => _configureItem(item),
                leading: Icon(
                  item.icon,
                  color: item.isConfigured ? Colors.green : Colors.amber.shade800,
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item.subtitle,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: item.isConfigured
                        ? Colors.green.withOpacity(0.1)
                        : Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.isConfigured ? Icons.check_circle : Icons.warning_amber,
                        size: 14,
                        color: item.isConfigured
                            ? Colors.green
                            : Colors.amber.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.isConfigured ? 'Configured' : 'Not configured',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: item.isConfigured
                              ? Colors.green
                              : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 28),

          // Activate Project Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isFullyReady ? Colors.green : Colors.grey.shade400,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.rocket_launch),
            label: const Text(
              'Activate Project',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: _isFullyReady
                ? _activateProject
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Configure all items before activating the project.',
                        ),
                        backgroundColor: Colors.amber,
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }
}