import 'package:flutter/material.dart';
import '../../models/project_models.dart';

class AddProjectPage extends StatefulWidget {
  // Pass an optional project. If null -> Create mode. If provided -> Edit mode.
  final Project? projectToEdit;

  const AddProjectPage({super.key, this.projectToEdit});

  @override
  State<AddProjectPage> createState() => _AddProjectPageState();
}

class _AddProjectPageState extends State<AddProjectPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _objectiveController;
  late final TextEditingController _locationController;
  late final TextEditingController _organizationController;
  late final TextEditingController _managerController;

  DateTime? _startDate;
  DateTime? _endDate;

  // Convenience getter to check if we are editing
  bool get _isEditing => widget.projectToEdit != null;

  @override
  void initState() {
    super.initState();
    // Pre-fill controllers with existing project data if editing
    final project = widget.projectToEdit;
    _nameController = TextEditingController(text: project?.name ?? '');
    _descriptionController = TextEditingController(text: project?.description ?? '');
    _objectiveController = TextEditingController(text: project?.objective ?? '');
    _locationController = TextEditingController(text: project?.location ?? '');
    _organizationController = TextEditingController(text: project?.organization ?? '');
    _managerController = TextEditingController(text: project?.manager ?? '');
    _startDate = project?.startDate;
    _endDate = project?.endDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _objectiveController.dispose();
    _locationController.dispose();
    _organizationController.dispose();
    _managerController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStartDate}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStartDate ? _startDate : _endDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final updatedProjectData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'objective': _objectiveController.text.trim(),
        'location': _locationController.text.trim(),
        'organization': _organizationController.text.trim(),
        'manager': _managerController.text.trim(),
        'startDate': _startDate,
        'endDate': _endDate,
      };

      Navigator.pop(context, updatedProjectData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Dynamic title based on mode
        title: Text(_isEditing ? 'Edit Project' : 'New Project'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _submitForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name *',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Please enter a name' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _objectiveController,
              decoration: const InputDecoration(
                labelText: 'Objective',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _organizationController,
                    decoration: const InputDecoration(
                      labelText: 'Organization',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _managerController,
                    decoration: const InputDecoration(
                      labelText: 'Project Manager',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ListTile(
                    tileColor: Colors.grey.shade100,
                    title: const Text('Start Date'),
                    subtitle: Text(_startDate == null
                        ? 'Select date'
                        : '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isStartDate: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ListTile(
                    tileColor: Colors.grey.shade100,
                    title: const Text('End Date'),
                    subtitle: Text(_endDate == null
                        ? 'Select date'
                        : '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isStartDate: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: const Color(0xFF005B7F),
                foregroundColor: Colors.white,
              ),
              // Dynamic button text
              child: Text(
                _isEditing ? 'Save Changes' : 'Create Project',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}