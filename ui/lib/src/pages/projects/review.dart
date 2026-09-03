import 'package:flutter/material.dart';

import '../../models/project_models.dart';
import 'prepare.dart';

class ProjectReviewPage extends StatefulWidget {
  final Project project;

  const ProjectReviewPage({super.key, required this.project});

  @override
  State<ProjectReviewPage> createState() => _ProjectReviewPageState();
}

class _ProjectReviewPageState extends State<ProjectReviewPage> {
  late ProjectState _currentState;
  final List<ReviewAction> _history = [];
  final TextEditingController _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentState = widget.project.state;
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // Update state and record history entry
  void _transitionState(ProjectState newState, String comment) {
    setState(() {
      _history.add(
        ReviewAction(
          previousState: _currentState,
          newState: newState,
          comment: comment,
          reviewerName: 'Current User', // Replace with logged-in user
          timestamp: DateTime.now(),
        ),
      );
      _currentState = newState;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Project status updated to ${newState.label}')),
    );
  }

  // Modal dialog to capture required reviewer feedback
  void _showCommentDialog({
    required String title,
    required ProjectState targetState,
    required String buttonLabel,
    required Color buttonColor,
  }) {
    _commentController.clear();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Enter reason or required changes...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (_commentController.text.trim().isNotEmpty) {
                  Navigator.pop(context);
                  _transitionState(targetState, _commentController.text.trim());
                }
              },
              child: Text(buttonLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Review Workflow'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Project Overview Header
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.project.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text(
                        'Current Status: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      // Status Chip using Enum color and label
                      Chip(
                        avatar: CircleAvatar(
                          backgroundColor: _currentState.color,
                        ),
                        label: Text(
                          _currentState.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        backgroundColor: _currentState.color.withValues(alpha: 0.85),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Contextual Action Buttons based on current state
          const Text(
            'Review Actions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildActionPanel(),

          const Divider(height: 40),

          // Audit Trail / History Log
          const Text(
            'Workflow Audit History',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_history.isEmpty)
            const Text(
              'No review updates logged yet.',
              style: TextStyle(color: Colors.grey),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final action = _history[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8.0),
                  child: ListTile(
                    leading: Icon(Icons.history, color: action.newState.color),
                    title: Text(
                      '${action.previousState.label} ➔ ${action.newState.label}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (action.comment.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text('"${action.comment}"'),
                          ),
                        Text(
                          'By ${action.reviewerName} on ${action.timestamp.hour}:${action.timestamp.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // Dynamic panel rendering valid buttons according to current status
  Widget _buildActionPanel() {
    switch (_currentState) {
      case ProjectState.submitted:
      case ProjectState.underReview:
      case ProjectState.amending:
        return Column(
          children: [
            Row(
              children: [
                // Accept Action
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Accept'),
                    onPressed: () => _transitionState(
                      ProjectState.accepted,
                      'Project accepted.',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Reject Action
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.cancel),
                    label: const Text('Reject'),
                    onPressed: () => _showCommentDialog(
                      title: 'Reject Project',
                      targetState: ProjectState.rejected,
                      buttonLabel: 'Reject',
                      buttonColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Request Amendment Action
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade800,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: const Icon(Icons.edit_note),
                label: const Text('Request Amendment'),
                onPressed: () => _showCommentDialog(
                  title: 'Request Project Amendment',
                  targetState: ProjectState.amendmentRequested,
                  buttonLabel: 'Send Request',
                  buttonColor: Colors.amber.shade800,
                ),
              ),
            ),
          ],
        );

      case ProjectState.amendmentRequested:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.build),
            label: const Text('Mark as Amending'),
            onPressed: () => _transitionState(
              ProjectState.amending,
              'User started amending project.',
            ),
          ),
        );

      case ProjectState.accepted:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Move to Preparation'),
            onPressed: () {
              _transitionState(
                ProjectState.preparation,
                'Project moved to preparation.',
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProjectPreparationPage(project: widget.project),
                ),
              );
            },
          ),
        );

      default:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'No actions available for state: ${_currentState.label}',
            style: const TextStyle(color: Colors.black54),
          ),
        );
    }
  }
}