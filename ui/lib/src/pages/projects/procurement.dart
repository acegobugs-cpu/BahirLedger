import 'package:flutter/material.dart';

// Types of procurement items
enum ProcurementCategory {
  materials('Materials & Supplies', Icons.inventory_2_outlined),
  equipment('Equipment & Tools', Icons.build_outlined),
  services('External Services / Contractors', Icons.handshake_outlined),
  software('Software & Licensing', Icons.computer_outlined);

  final String label;
  final IconData icon;
  const ProcurementCategory(this.label, this.icon);
}

// Acquisition Status
enum ProcurementStatus {
  planned('Planned', Colors.grey),
  sourcing('Sourcing Vendor', Colors.orange),
  ordered('Order Placed', Colors.blue),
  received('Received / Active', Colors.green);

  final String label;
  final Color color;
  const ProcurementStatus(this.label, this.color);
}

// Item Model linking Budget -> Asset
class ProcurementItem {
  String id;
  String name;
  ProcurementCategory category;
  double estimatedCost;
  ProcurementStatus status;
  String preferredSupplier;

  ProcurementItem({
    required this.id,
    required this.name,
    required this.category,
    required this.estimatedCost,
    this.status = ProcurementStatus.planned,
    this.preferredSupplier = '',
  });
}

class ProjectProcurementPage extends StatefulWidget {
  final String projectName;

  const ProjectProcurementPage({
    super.key,
    required this.projectName,
  });

  @override
  State<ProjectProcurementPage> createState() => _ProjectProcurementPageState();
}

class _ProjectProcurementPageState extends State<ProjectProcurementPage> {
  final List<ProcurementItem> _items = [];

  final _nameController = TextEditingController();
  final _costController = TextEditingController();
  final _supplierController = TextEditingController();
  ProcurementCategory _selectedCategory = ProcurementCategory.materials;
  ProcurementStatus _selectedStatus = ProcurementStatus.planned;

  @override
  void dispose() {
    _nameController.dispose();
    _costController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  void _showItemDialog({ProcurementItem? existingItem}) {
    if (existingItem != null) {
      _nameController.text = existingItem.name;
      _costController.text = existingItem.estimatedCost.toStringAsFixed(2);
      _supplierController.text = existingItem.preferredSupplier;
      _selectedCategory = existingItem.category;
      _selectedStatus = existingItem.status;
    } else {
      _nameController.clear();
      _costController.clear();
      _supplierController.clear();
      _selectedCategory = ProcurementCategory.materials;
      _selectedStatus = ProcurementStatus.planned;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(existingItem == null
                  ? 'Add Procurement Item'
                  : 'Edit Procurement Item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Goods / Service Name',
                        hintText: 'e.g., Solar Panels, Structural Engineering',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ProcurementCategory>(
                      value: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: ProcurementCategory.values.map((cat) {
                        return DropdownMenuItem(
                          value: cat,
                          child: Row(
                            children: [
                              Icon(cat.icon, size: 18, color: const Color(0xFF005B7F)),
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
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Estimated Cost (\$) ',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _supplierController,
                      decoration: const InputDecoration(
                        labelText: 'Preferred Supplier / Vendor',
                        hintText: 'e.g., Acme Corp (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<ProcurementStatus>(
                      value: _selectedStatus,
                      decoration: const InputDecoration(
                        labelText: 'Procurement Stage',
                        border: OutlineInputBorder(),
                      ),
                      items: ProcurementStatus.values.map((status) {
                        return DropdownMenuItem(
                          value: status,
                          child: Row(
                            children: [
                              CircleAvatar(radius: 5, backgroundColor: status.color),
                              const SizedBox(width: 8),
                              Text(status.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => _selectedStatus = val);
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
                    final name = _nameController.text.trim();
                    final cost = double.tryParse(_costController.text.trim()) ?? 0.0;
                    final supplier = _supplierController.text.trim();

                    if (name.isNotEmpty) {
                      setState(() {
                        if (existingItem != null) {
                          existingItem.name = name;
                          existingItem.category = _selectedCategory;
                          existingItem.estimatedCost = cost;
                          existingItem.status = _selectedStatus;
                          existingItem.preferredSupplier = supplier;
                        } else {
                          _items.add(
                            ProcurementItem(
                              id: DateTime.now().toString(),
                              name: name,
                              category: _selectedCategory,
                              estimatedCost: cost,
                              status: _selectedStatus,
                              preferredSupplier: supplier,
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
      _items.removeWhere((item) => item.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalProcurementCost = _items.fold<double>(0, (sum, i) => sum + i.estimatedCost);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Procurement Plan'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Chain Tracker: Budget → Procurement → Supplier → Purchase → Asset',
                    style: TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  const Divider(color: Colors.white24, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Items: ${_items.length}', style: const TextStyle(color: Colors.white)),
                      Text(
                        'Est. Total: \$${totalProcurementCost.toStringAsFixed(2)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Acquisition Requirements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
                onPressed: () => _showItemDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_items.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(Icons.shopping_cart_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('No goods or services listed.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)),
                  SizedBox(height: 4),
                  Text('Tap "Add Item" to specify materials, services, or equipment needed.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF70B4C8).withOpacity(0.2),
                      child: Icon(item.category.icon, color: const Color(0xFF005B7F)),
                    ),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.category.label} • Est: \$${item.estimatedCost.toStringAsFixed(2)}'),
                        if (item.preferredSupplier.isNotEmpty)
                          Text('Supplier: ${item.preferredSupplier}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          backgroundColor: item.status.color.withOpacity(0.15),
                          side: BorderSide.none,
                          label: Text(
                            item.status.label,
                            style: TextStyle(fontSize: 10, color: item.status.color, fontWeight: FontWeight.bold),
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

          // Save Configuration
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B7F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              Navigator.pop(context, {
                'isConfigured': _items.isNotEmpty,
                'items': _items,
              });
            },
            child: const Text('Save Procurement Plan', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}