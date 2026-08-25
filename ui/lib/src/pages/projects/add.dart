import 'package:flutter/material.dart';

class AddProjectPage extends StatefulWidget {
  const AddProjectPage({super.key});

  @override
  State<AddProjectPage> createState() => _AddProjectPageState();
}

class _AddProjectPageState extends State<AddProjectPage> {
  // Global key to track form state and perform validation
  final _formKey = GlobalKey<FormState>();

  // Text Controllers for input fields
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _objectiveController = TextEditingController();
  final _locationController = TextEditingController();
  final _organizationController = TextEditingController();
  final _managerController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;

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
      initialDate: DateTime.now(),
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
      // Package up form data into a Map (or your Model object later)
      final newProjectData = {
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'objective': _objectiveController.text.trim(),
        'location': _locationController.text.trim(),
        'organization': _organizationController.text.trim(),
        'manager': _managerController.text.trim(),
        'startDate': _startDate,
        'endDate': _endDate,
      };

      // Return data to previous screen
      Navigator.pop(context, newProjectData);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Project'),
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
            // Project Name
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

            // Description (Multi-line text field like <textarea>)
            TextFormField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Objective
            TextFormField(
              controller: _objectiveController,
              decoration: const InputDecoration(
                labelText: 'Objective',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Two-column layout for Organization & Manager
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

            // Location
            TextFormField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Location',
                prefixIcon: Icon(Icons.location_on),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Dates Pickers Row
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

            // Big Save Button
            ElevatedButton(
              onPressed: _submitForm,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: const Text('Create Project', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}