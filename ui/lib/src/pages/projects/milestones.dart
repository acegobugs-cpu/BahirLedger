import 'package:flutter/material.dart';

// Model for Milestone / Key Deliverable
class ProjectMilestone {
  String id;
  String title;
  String deliverable;
  DateTime targetDate;
  bool isCriticalPath;

  ProjectMilestone({
    required this.id,
    required this.title,
    required this.deliverable,
    required this.targetDate,
    this.isCriticalPath = false,
  });
}

class ProjectMilestonesPage extends StatefulWidget {
  final String projectName;

  const ProjectMilestonesPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ProjectMilestonesPage> createState() => _ProjectMilestonesPageState();
}

class _ProjectMilestonesPageState extends State<ProjectMilestonesPage> {
  final List<ProjectMilestone> _milestones = [];

  final _titleController = TextEditingController();
  final _deliverableController = TextEditingController();
  DateTime? _selectedDate;
  bool _isCriticalPath = false;

  @override
  void dispose() {
    _titleController.dispose();
    _deliverableController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select Date';
    return '${date.day}/${date.month}/${date.year}';
  }

  // Opens modal dialog to add/edit milestone
  void _showMilestoneDialog({ProjectMilestone? existingItem}) {
    if (existingItem != null) {
      _titleController.text = existingItem.title;
      _deliverableController.text = existingItem.deliverable;
      _selectedDate = existingItem.targetDate;
      _isCriticalPath = existingItem.isCriticalPath;
    } else {
      _titleController.clear();
      _deliverableController.clear();
      _selectedDate = DateTime.now().add(const Duration(days: 30));
      _isCriticalPath = false;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(existingItem == null
                  ? 'Add Milestone'
                  : 'Edit Milestone'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Milestone Title',
                        hintText: 'e.g., Phase 1 Completion',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _deliverableController,
                      decoration: const InputDecoration(
                        labelText: 'Key Deliverable',
                        hintText: 'e.g., Environmental Impact Report',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Target Date Picker Tile
                    ListTile(
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      leading: const Icon(Icons.calendar_month, color: Color(0xFF005B7F)),
                      title: const Text('Target Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      subtitle: Text(
                        _formatDate(_selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 3650)),
                        );
                        if (picked != null) {
                          setModalState(() => _selectedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Critical Path Switch
                    SwitchListTile(
                      title: const Text('Critical Path Item'),
                      subtitle: const Text('Delays will impact overall launch'),
                      value: _isCriticalPath,
                      activeThumbColor: Colors.redAccent,
                      onChanged: (val) {
                        setModalState(() => _isCriticalPath = val);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF005B7F),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final title = _titleController.text.trim();
                    final deliverable = _deliverableController.text.trim();

                    if (title.isNotEmpty && _selectedDate != null) {
                      setState(() {
                        if (existingItem != null) {
                          existingItem.title = title;
                          existingItem.deliverable = deliverable;
                          existingItem.targetDate = _selectedDate!;
                          existingItem.isCriticalPath = _isCriticalPath;
                        } else {
                          _milestones.add(
                            ProjectMilestone(
                              id: DateTime.now().toString(),
                              title: title,
                              deliverable: deliverable,
                              targetDate: _selectedDate!,
                              isCriticalPath: _isCriticalPath,
                            ),
                          );
                        }
                        // Sort chronologically
                        _milestones.sort((a, b) => a.targetDate.compareTo(b.targetDate));
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Milestone'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteMilestone(String id) {
    setState(() {
      _milestones.removeWhere((item) => item.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final criticalCount = _milestones.where((m) => m.isCriticalPath).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Milestones'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Summary
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Milestones: ${_milestones.length}', style: const TextStyle(color: Colors.white70)),
                      Text(
                        'Critical Path: $criticalCount',
                        style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Action Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Timeline & Deliverables', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Milestone'),
                onPressed: () => _showMilestoneDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_milestones.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(Icons.flag_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No milestones set yet.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  SizedBox(height: 4),
                  Text('Tap "Add Milestone" to sequence key project deliverables.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _milestones.length,
              itemBuilder: (context, index) {
                final item = _milestones[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.isCriticalPath ? Colors.red.shade100 : const Color(0xFF70B4C8).withValues(alpha: 0.3),
                      child: Icon(
                        Icons.flag,
                        color: item.isCriticalPath ? Colors.red : const Color(0xFF005B7F),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (item.isCriticalPath) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('CRITICAL', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red)),
                          ),
                        ]
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.deliverable.isNotEmpty) Text('Deliverable: ${item.deliverable}'),
                        Text('Target Date: ${_formatDate(item.targetDate)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onPressed: () => _showMilestoneDialog(existingItem: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _deleteMilestone(item.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 32),

          // Save Configuration
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B7F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              Navigator.pop(context, {
                'isConfigured': _milestones.isNotEmpty,
                'milestones': _milestones,
              });
            },
            child: const Text('Save Milestones Configuration', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}