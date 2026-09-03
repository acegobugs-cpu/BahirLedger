import 'package:flutter/material.dart';

import '../../models/project_models.dart';
import '../../data/projects.dart';
import 'add.dart';
import 'detail.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsState();
}

class _ProjectsState extends State<ProjectsPage> {

  // A dynamic list to hold our project names (our local State)
  final List<Project> _projects = sampleProjects; // Using the sample dataset

  // 3. Function to show the input dialog popup
  void _showAddProjectDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddProjectPage()),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _projects.add(
          Project(
            name: result['name'],
            description: result['description'],
            objective: result['objective'],
            location: result['location'],
            organization: result['organization'],
            manager: result['manager'],
            startDate: result['startDate'],
            endDate: result['endDate'],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Floating Action Button (bottom right "+" button)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProjectDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Project'),
        backgroundColor: Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Active Projects',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _projects.length,
                itemBuilder: (context, index) {
                  final project = _projects[index];
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.folder, color: Color(0xFF005B7F)),
                      title: Text(project.name),
                      subtitle: Text(
                        project.manager.isNotEmpty
                            ? 'PM: ${project.manager}'
                            : 'No PM assigned',
                      ),
                      trailing: Chip(
                        label: Text(
                          project.state.label,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        backgroundColor: project.state.color,
                      ),
                      // Tapping navigates to the Read/Details page
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ProjectDetailsPage(project: project),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}