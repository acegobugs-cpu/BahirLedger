class Project {
  final String name;
  final String description;
  final String objective;
  final String location;
  final String organization;
  final String manager;
  final DateTime? startDate;
  final DateTime? endDate;

  Project({
    required this.name,
    this.description = '',
    this.objective = '',
    this.location = '',
    this.organization = '',
    this.manager = '',
    this.startDate,
    this.endDate,
  });
}