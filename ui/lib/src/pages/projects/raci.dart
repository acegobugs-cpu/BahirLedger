import 'package:flutter/material.dart';

// Standard RACI Role Definition
enum RaciRole {
  responsible(
    'Responsible',
    'R',
    'Doer of the activity',
    Colors.blue,
  ),
  accountable(
    'Accountable',
    'A',
    'Final decision maker / Owner',
    Colors.purple,
  ),
  consulted(
    'Consulted',
    'C',
    'Provides required input',
    Colors.orange,
  ),
  informed(
    'Informed',
    'I',
    'Kept updated on progress',
    Colors.teal,
  );

  final String label;
  final String code;
  final String description;
  final Color color;

  const RaciRole(this.label, this.code, this.description, this.color);
}

// Single RACI Assignment Entry
class RaciAssignment {
  String id;
  String taskName;
  String memberName;
  RaciRole role;

  RaciAssignment({
    required this.id,
    required this.taskName,
    required this.memberName,
    required this.role,
  });
}

class ProjectResponsibilitiesPage extends StatefulWidget {
  final String projectName;

  const ProjectResponsibilitiesPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ProjectResponsibilitiesPage> createState() =>
      _ProjectResponsibilitiesPageState();
}

class _ProjectResponsibilitiesPageState
    extends State<ProjectResponsibilitiesPage> {
  final List<RaciAssignment> _assignments = [];

  final _taskController = TextEditingController();
  final _memberController = TextEditingController();
  RaciRole _selectedRole = RaciRole.responsible;

  @override
  void dispose() {
    _taskController.dispose();
    _memberController.dispose();
    super.dispose();
  }

  // Opens a modal dialog to create or edit a RACI matrix assignment
  void _showAssignmentDialog({RaciAssignment? existingAssignment}) {
    if (existingAssignment != null) {
      _taskController.text = existingAssignment.taskName;
      _memberController.text = existingAssignment.memberName;
      _selectedRole = existingAssignment.role;
    } else {
      _taskController.clear();
      _memberController.clear();
      _selectedRole = RaciRole.responsible;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                existingAssignment == null
                    ? 'Add RACI Assignment'
                    : 'Edit RACI Assignment',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _taskController,
                      decoration: const InputDecoration(
                        labelText: 'Task / Deliverable',
                        hintText: 'e.g., Site Assessment, Vendor Selection',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _memberController,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Stakeholder / Team Member',
                        hintText: 'e.g., Jane Doe, Field Operations Team',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<RaciRole>(
                      initialValue: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: 'RACI Role',
                        border: OutlineInputBorder(),
                      ),
                      items: RaciRole.values.map((role) {
                        return DropdownMenuItem(
                          value: role,
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 10,
                                backgroundColor: role.color,
                                child: Text(
                                  role.code,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('${role.label} (${role.code})'),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => _selectedRole = val);
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
                    final task = _taskController.text.trim();
                    final member = _memberController.text.trim();

                    if (task.isNotEmpty && member.isNotEmpty) {
                      setState(() {
                        if (existingAssignment != null) {
                          existingAssignment.taskName = task;
                          existingAssignment.memberName = member;
                          existingAssignment.role = _selectedRole;
                        } else {
                          _assignments.add(
                            RaciAssignment(
                              id: DateTime.now().toString(),
                              taskName: task,
                              memberName: member,
                              role: _selectedRole,
                            ),
                          );
                        }
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Assignment'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteAssignment(String id) {
    setState(() {
      _assignments.removeWhere((item) => item.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RACI Responsibilities Matrix'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Legend Card
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'RACI Framework Quick Guide',
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: RaciRole.values.map((role) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 8,
                              backgroundColor: role.color,
                              child: Text(
                                role.code,
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${role.label} (${role.code})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Assignments List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Matrix Assignments',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Assignment'),
                onPressed: () => _showAssignmentDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_assignments.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.assignment_ind_outlined,
                    size: 48,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No RACI roles configured.',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap "Add Assignment" to map stakeholders to tasks using the RACI framework.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final item = _assignments[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: item.role.color,
                      child: Text(
                        item.role.code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      item.taskName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Assigned: ${item.memberName}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          backgroundColor: item.role.color.withValues(alpha: 0.15),
                          label: Text(
                            item.role.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: item.role.color,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onPressed: () =>
                              _showAssignmentDialog(existingAssignment: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _deleteAssignment(item.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 32),

          // Save Configuration Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B7F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              Navigator.pop(context, {
                'isConfigured': _assignments.isNotEmpty,
                'assignments': _assignments,
              });
            },
            child: const Text(
              'Save Responsibilities Configuration',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}