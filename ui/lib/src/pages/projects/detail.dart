import 'package:flutter/material.dart';

import '../../models/project_models.dart';
import 'add.dart';
import 'review.dart'; // Import review page if needed

class ProjectDetailsPage extends StatefulWidget {
  final Project project;

  const ProjectDetailsPage({super.key, required this.project});

  @override
  State<ProjectDetailsPage> createState() => _ProjectDetailsPageState();
}

class _ProjectDetailsPageState extends State<ProjectDetailsPage> {
  late Project _currentProject;

  // Mock list of users available for assignment/review
  final List<String> _reviewers = [
    'Alice Johnson (Lead Reviewer)',
    'Bob Smith (Regional Director)',
    'Carol Danvers (Department Head)',
  ];

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _openEditPage() async {
    final updatedData = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddProjectPage(projectToEdit: _currentProject),
      ),
    );

    if (updatedData != null && updatedData is Map<String, dynamic>) {
      setState(() {
        _currentProject = Project(
          name: updatedData['name'],
          description: updatedData['description'],
          objective: updatedData['objective'],
          location: updatedData['location'],
          organization: updatedData['organization'],
          manager: updatedData['manager'],
          startDate: updatedData['startDate'],
          endDate: updatedData['endDate'],
          state: _currentProject.state,
        );
      });
    }
  }

  // Opens a selection dialog to pick a reviewer before submitting
  void _showSubmitDialog() {
    String? selectedReviewer = _reviewers.first;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Submit for Review'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select the reviewer or approver for this project:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedReviewer,
                    decoration: const InputDecoration(
                      labelText: 'Select Reviewer',
                      border: OutlineInputBorder(),
                    ),
                    items: _reviewers.map((reviewer) {
                      return DropdownMenuItem(
                        value: reviewer,
                        child: Text(reviewer, style: const TextStyle(fontSize: 14)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setModalState(() {
                        selectedReviewer = value;
                      });
                    },
                  ),
                ],
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
                    Navigator.pop(context); // Close modal
                    
                    // Update state to submitted
                    setState(() {
                      _currentProject = Project(
                        name: _currentProject.name,
                        description: _currentProject.description,
                        objective: _currentProject.objective,
                        location: _currentProject.location,
                        organization: _currentProject.organization,
                        manager: _currentProject.manager,
                        startDate: _currentProject.startDate,
                        endDate: _currentProject.endDate,
                        state: ProjectState.submitted, // State transition!
                      );
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Submitted to $selectedReviewer for review!'),
                      ),
                    );
                  },
                  child: const Text('Confirm & Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only allow submission if project is currently in Draft or Amending state
    final bool canSubmit = _currentProject.state == ProjectState.draft ||
        _currentProject.state == ProjectState.amending;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentProject.name),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Project',
            onPressed: _openEditPage,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          Card(
            color: const Color(0xFF70B4C8),
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentProject.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF005B7F),
                    ),
                  ),
                  if (_currentProject.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _currentProject.description,
                      style: const TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Status & Details List Section
          _buildDetailTile(
            icon: Icons.health_and_safety,
            title: 'status',
            value: _currentProject.state.label,
          ),
          _buildDetailTile(
            icon: Icons.flag,
            title: 'Objective',
            value: _currentProject.objective,
          ),
          _buildDetailTile(
            icon: Icons.location_on,
            title: 'Location',
            value: _currentProject.location,
          ),
          _buildDetailTile(
            icon: Icons.business,
            title: 'Organization',
            value: _currentProject.organization,
          ),
          _buildDetailTile(
            icon: Icons.person,
            title: 'Project Manager',
            value: _currentProject.manager,
          ),
          const Divider(height: 32),

          // Timeline Dates Row
          Row(
            children: [
              Expanded(
                child: _buildDetailTile(
                  icon: Icons.calendar_today,
                  title: 'Start Date',
                  value: _formatDate(_currentProject.startDate),
                ),
              ),
              Expanded(
                child: _buildDetailTile(
                  icon: Icons.event,
                  title: 'Expected End Date',
                  value: _formatDate(_currentProject.endDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Submit Action Button (Shown when project is in draft/amending state)
          if (canSubmit)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF005B7F),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.send),
              label: const Text('Submit for Review', style: TextStyle(fontSize: 16)),
              onPressed: _showSubmitDialog,
            )
          else
            // Optional button to open the Review Workflow page directly if already submitted
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: const Icon(Icons.rate_review),
              label: const Text('Open Review Panel', style: TextStyle(fontSize: 16)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProjectReviewPage(project: _currentProject),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDetailTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF005B7F)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? 'Not specified' : value,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}