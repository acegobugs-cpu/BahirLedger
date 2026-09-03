import 'package:flutter/material.dart';

// Budget Category Enum
enum BudgetCategory {
  personnel('Personnel & Labor', Icons.people),
  equipment('Equipment & Machinery', Icons.construction),
  materials('Materials & Supplies', Icons.inventory),
  logistics('Logistics & Travel', Icons.local_shipping),
  overhead('Overhead & Admin', Icons.business);

  final String label;
  final IconData icon;
  const BudgetCategory(this.label, this.icon);
}

// Model for individual budget line items
class BudgetItem {
  String id;
  String name;
  BudgetCategory category;
  double allocatedAmount;

  BudgetItem({
    required this.id,
    required this.name,
    required this.category,
    required this.allocatedAmount,
  });
}

class ProjectBudgetPage extends StatefulWidget {
  final String projectName;
  final double costCap; // Maximum total allowed budget limit

  const ProjectBudgetPage({
    super.key,
    required this.projectName,
    this.costCap = 150000.00, // Example overall project limit
  });

  @override
  State<ProjectBudgetPage> createState() => _ProjectBudgetPageState();
}

class _ProjectBudgetPageState extends State<ProjectBudgetPage> {
  final List<BudgetItem> _budgetItems = [];

  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  BudgetCategory _selectedCategory = BudgetCategory.personnel;

  double get _totalAllocated =>
      _budgetItems.fold(0.0, (sum, item) => sum + item.allocatedAmount);

  bool get _isExceedingCap => _totalAllocated > widget.costCap;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // Opens dialog to create or edit a budget line item
  void _showItemDialog({BudgetItem? existingItem}) {
    if (existingItem != null) {
      _nameController.text = existingItem.name;
      _amountController.text = existingItem.allocatedAmount.toString();
      _selectedCategory = existingItem.category;
    } else {
      _nameController.clear();
      _amountController.clear();
      _selectedCategory = BudgetCategory.personnel;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(existingItem == null ? 'Add Line Item' : 'Edit Line Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Item Description',
                        hintText: 'e.g., Solar Water Pump, Site Engineers',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<BudgetCategory>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: BudgetCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Row(
                            children: [
                              Icon(cat.icon, size: 20, color: const Color(0xFF005B7F)),
                              const SizedBox(width: 8),
                              Text(cat.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => _selectedCategory = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Allocated Amount (\$)',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
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
                    final name = _nameController.text.trim();
                    final amount = double.tryParse(_amountController.text.trim()) ?? 0;

                    if (name.isNotEmpty && amount > 0) {
                      setState(() {
                        if (existingItem != null) {
                          existingItem.name = name;
                          existingItem.allocatedAmount = amount;
                          existingItem.category = _selectedCategory;
                        } else {
                          _budgetItems.add(
                            BudgetItem(
                              id: DateTime.now().toString(),
                              name: name,
                              category: _selectedCategory,
                              allocatedAmount: amount,
                            ),
                          );
                        }
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Item'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteItem(String id) {
    setState(() {
      _budgetItems.removeWhere((item) => item.id == id);
    });
  }

  // Calculate totals grouped by category
  Map<BudgetCategory, double> get _categoryTotals {
    final Map<BudgetCategory, double> map = {};
    for (var cat in BudgetCategory.values) {
      map[cat] = 0.0;
    }
    for (var item in _budgetItems) {
      map[item.category] = (map[item.category] ?? 0) + item.allocatedAmount;
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final double budgetRatio = (widget.costCap > 0)
        ? (_totalAllocated / widget.costCap).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Project Budget'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Cost Cap Visual Tracker Card
          Card(
            color: _isExceedingCap ? Colors.red.shade900 : const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Budget Allocated:', style: TextStyle(color: Colors.white)),
                      Text(
                        '\$${_totalAllocated.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _isExceedingCap ? Colors.amberAccent : Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cost Cap Limit:', style: TextStyle(color: Colors.white70)),
                      Text(
                        '\$${widget.costCap.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: budgetRatio,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isExceedingCap ? Colors.amber : Colors.greenAccent,
                      ),
                    ),
                  ),
                  if (_isExceedingCap) ...[
                    const SizedBox(height: 10),
                    const Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.amberAccent, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Warning: Total allocations exceed the project cost cap!',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ]
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Category Expense Breakdown Summary
          const Text(
            'Category Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categoryTotals.entries.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(entry.key.icon, size: 16, color: const Color(0xFF005B7F)),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key.label,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                          Text(
                            '\$${entry.value.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // Line Items List Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Line Items',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Line Item'),
                onPressed: () => _showItemDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_budgetItems.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'No budget items added yet.',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap "Add Line Item" to define specific project expense allocations.',
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
              itemCount: _budgetItems.length,
              itemBuilder: (context, index) {
                final item = _budgetItems[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF70B4C8).withOpacity(0.3),
                      child: Icon(item.category.icon, color: const Color(0xFF005B7F)),
                    ),
                    title: Text(
                      item.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(item.category.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '\$${item.allocatedAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onPressed: () => _showItemDialog(existingItem: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _deleteItem(item.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 32),

          // Save Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B7F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              Navigator.pop(context, {
                'isConfigured': _budgetItems.isNotEmpty && !_isExceedingCap,
                'totalAllocated': _totalAllocated,
                'costCap': widget.costCap,
                'items': _budgetItems,
              });
            },
            child: const Text('Save Budget Configuration', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}