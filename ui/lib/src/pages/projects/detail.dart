import 'package:flutter/material.dart';

import '../../models/project_models.dart';

class ProjectDetailsPage extends StatelessWidget {
  // We pass the tapped Project into this widget constructor
  final Project project;

  const ProjectDetailsPage({super.key, required this.project});

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          Card(
            color: Colors.indigo.shade50,
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  if (project.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      project.description,
                      style: const TextStyle(fontSize: 16, color: Colors.black),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Details List Section
          _buildDetailTile(
            icon: Icons.flag,
            title: 'Objective',
            value: project.objective,
          ),
          _buildDetailTile(
            icon: Icons.location_on,
            title: 'Location',
            value: project.location,
          ),
          _buildDetailTile(
            icon: Icons.business,
            title: 'Organization',
            value: project.organization,
          ),
          _buildDetailTile(
            icon: Icons.person,
            title: 'Project Manager',
            value: project.manager,
          ),
          const Divider(height: 32),

          // Timeline Dates Row
          Row(
            children: [
              Expanded(
                child: _buildDetailTile(
                  icon: Icons.calendar_today,
                  title: 'Start Date',
                  value: _formatDate(project.startDate),
                ),
              ),
              Expanded(
                child: _buildDetailTile(
                  icon: Icons.event,
                  title: 'Expected End Date',
                  value: _formatDate(project.endDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper method to keep UI clean and consistent
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
          Icon(icon, color: Colors.indigo),
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