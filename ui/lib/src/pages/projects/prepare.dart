import 'package:flutter/material.dart';

import '../../models/project_models.dart';
import 'budget.dart';
import 'funding.dart';
import 'milestones.dart';
import 'procurement.dart';
import 'raci.dart';

// Preparation status item state model
class ReadinessItem {
  final String key; // Unique identifier matching sub-pages
  final String title;
  final String subtitle;
  final IconData icon;
  bool isConfigured;

  ReadinessItem({
    required this.key,
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
  late final List<ReadinessItem> _readinessItems;

  @override
  void initState() {
    super.initState();
    _readinessItems = [
      ReadinessItem(
        key: 'funding',
        title: 'Funding',
        subtitle: 'Grants, loans, and donor funding sources',
        icon: Icons.account_balance,
        isConfigured: false,
      ),
      ReadinessItem(
        key: 'budget',
        title: 'Budget',
        subtitle: 'Line-item breakdown and cost caps',
        icon: Icons.attach_money,
        isConfigured: false,
      ),
      ReadinessItem(
        key: 'team',
        title: 'Team',
        subtitle: 'Assigned staff and external contacts',
        icon: Icons.groups,
        isConfigured: true, // Pre-configured from project creation
      ),
      ReadinessItem(
        key: 'responsibilities',
        title: 'Responsibilities',
        subtitle: 'RACI matrix and role assignments',
        icon: Icons.assignment_ind,
        isConfigured: false,
      ),
      ReadinessItem(
        key: 'milestones',
        title: 'Milestones',
        subtitle: 'Key deliverables and target dates',
        icon: Icons.flag,
        isConfigured: false,
      ),
      ReadinessItem(
        key: 'procurement',
        title: 'Procurement',
        subtitle: 'Equipment sourcing and vendor contracts',
        icon: Icons.shopping_cart,
        isConfigured: false,
      ),
      ReadinessItem(
        key: 'documents',
        title: 'Required Documents',
        subtitle: 'Permits, environmental clearance, compliance forms',
        icon: Icons.folder_special,
        isConfigured: true, // Pre-configured from compliance docs
      ),
    ];
  }

  // Calculate overall readiness percentage
  double get _readinessProgress {
    final completed = _readinessItems.where((item) => item.isConfigured).length;
    return completed / _readinessItems.length;
  }

  bool get _isFullyReady => _readinessProgress == 1.0;

  // Handles navigation and dynamic state updates from returned sub-page data
  Future<void> _handleTileTap(ReadinessItem item) async {
    dynamic result;

    switch (item.key) {
      case 'funding':
        result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectFundingPage(
              projectName: widget.project.name,
            ),
          ),
        );
        break;

      case 'budget':
        result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectBudgetPage(
              projectName: widget.project.name,
            ),
          ),
        );
        break;

      case 'responsibilities':
        result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectResponsibilitiesPage(
              projectName: widget.project.name,
            ),
          ),
        );
        break;

      case 'milestones':
        result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectMilestonesPage(
              projectName: widget.project.name,
            ),
          ),
        );
        break;

      case 'procurement':
        result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectProcurementPage(
              projectName: widget.project.name,
            ),
          ),
        );
        break;

      default:
        // Generic Modal fallback for static tiles (e.g. Team, Required Documents)
        _showDefaultConfigModal(item);
        return;
    }

    // Process result map returned from Navigator.pop()
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        item.isConfigured = result['isConfigured'] ?? false;
      });
    }
  }

  void _showDefaultConfigModal(ReadinessItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
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
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(item.subtitle, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              SwitchListTile(
                title: Text('Mark ${item.title} as complete'),
                value: item.isConfigured,
                activeThumbColor: Colors.green,
                onChanged: (val) {
                  setState(() {
                    item.isConfigured = val;
                  });
                  Navigator.pop(context);
                },
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
            'This will transition the status to Active and notify assigned team members.',
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
                Navigator.pop(context);
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
          // Header Summary Card with Dynamic Progress Bar
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Readiness: $configuredCount of $totalCount items',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
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

          // Readiness List Items with Action Chevron
          ..._readinessItems.map((item) {
            return Card(
              elevation: 0.5,
              margin: const EdgeInsets.symmetric(vertical: 6.0),
              child: ListTile(
                onTap: () => _handleTileTap(item),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.isConfigured
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            item.isConfigured ? Icons.check_circle : Icons.warning_amber,
                            size: 14,
                            color: item.isConfigured ? Colors.green : Colors.amber.shade900,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.isConfigured ? 'Configured' : 'Not configured',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: item.isConfigured ? Colors.green : Colors.amber.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
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
                          'Configure all 7 items before activating the project.',
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