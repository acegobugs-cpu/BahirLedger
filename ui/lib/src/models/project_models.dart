import 'package:flutter/material.dart';

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