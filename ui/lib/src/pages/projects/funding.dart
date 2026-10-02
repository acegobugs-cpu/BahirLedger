import 'package:flutter/material.dart';

// Funding Source Type Enum
enum FundingType {
  government('Government Allocation', Icons.account_balance),
  organization('Organization Funds', Icons.domain),
  donor('Donor / Grant', Icons.volunteer_activism),
  other('Other Source', Icons.payments);

  final String label;
  final IconData icon;
  const FundingType(this.label, this.icon);
}

// Model for individual funding contributions
class FundingSourceItem {
  String id;
  FundingType type;
  String providerName; // e.g., "Ministry of Water" or "USAID Grant"
  double amount;

  FundingSourceItem({
    required this.id,
    required this.type,
    required this.providerName,
    required this.amount,
  });
}

class ProjectFundingPage extends StatefulWidget {
  final String projectName;
  final double targetBudget; // Optional total budget limit to compare against

  const ProjectFundingPage({
    super.key,
    required this.projectName,
    this.targetBudget = 100000.00, // Example default budget
  });

  @override
  State<ProjectFundingPage> createState() => _ProjectFundingPageState();
}

class _ProjectFundingPageState extends State<ProjectFundingPage> {
  final List<FundingSourceItem> _fundingSources = [];

  // Controllers for adding/editing dynamic sources
  final _providerController = TextEditingController();
  final _amountController = TextEditingController();
  FundingType _selectedType = FundingType.government;

  double get _totalCommitted =>
      _fundingSources.fold(0.0, (sum, item) => sum + item.amount);

  @override
  void dispose() {
    _providerController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // Dialog to add or edit a funding source entry
  void _showFundingSourceDialog({FundingSourceItem? existingItem}) {
    if (existingItem != null) {
      _providerController.text = existingItem.providerName;
      _amountController.text = existingItem.amount.toString();
      _selectedType = existingItem.type;
    } else {
      _providerController.clear();
      _amountController.clear();
      _selectedType = FundingType.government;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(existingItem == null
                  ? 'Add Funding Source'
                  : 'Edit Funding Source'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<FundingType>(
                      initialValue: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Source Type',
                        border: OutlineInputBorder(),
                      ),
                      items: FundingType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Icon(type.icon, size: 20, color: const Color(0xFF005B7F)),
                              const SizedBox(width: 8),
                              Text(type.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => _selectedType = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _providerController,
                      decoration: const InputDecoration(
                        labelText: 'Provider / Funder Name',
                        hintText: 'e.g., World Bank, Ministry of Health',
                        border: OutlineInputBorder(),
                      ),
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
                    final provider = _providerController.text.trim();
                    final amount = double.tryParse(_amountController.text.trim()) ?? 0;

                    if (provider.isNotEmpty && amount > 0) {
                      setState(() {
                        if (existingItem != null) {
                          existingItem.providerName = provider;
                          existingItem.amount = amount;
                          existingItem.type = _selectedType;
                        } else {
                          _fundingSources.add(
                            FundingSourceItem(
                              id: DateTime.now().toString(),
                              type: _selectedType,
                              providerName: provider,
                              amount: amount,
                            ),
                          );
                        }
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save Source'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteSource(String id) {
    setState(() {
      _fundingSources.removeWhere((item) => item.id == id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final double fundingRatio = (widget.targetBudget > 0)
        ? (_totalCommitted / widget.targetBudget).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Project Funding'),
        backgroundColor: const Color(0xFF005B7F),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Header Card with Funding Summary
          Card(
            color: const Color(0xFF005B7F),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.projectName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Committed:', style: TextStyle(color: Colors.white70)),
                      Text(
                        '\$${_totalCommitted.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Target Budget:', style: TextStyle(color: Colors.white70)),
                      Text(
                        '\$${widget.targetBudget.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fundingRatio,
                      minHeight: 8,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        fundingRatio >= 1.0 ? Colors.greenAccent : Colors.amber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Funding Sources List Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Funding Sources',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Source'),
                onPressed: () => _showFundingSourceDialog(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_fundingSources.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Column(
                children: [
                  Icon(Icons.monetization_on_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'No funding sources configured yet.',
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Tap "Add Source" to register government, donor, or organization funding.',
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
              itemCount: _fundingSources.length,
              itemBuilder: (context, index) {
                final source = _fundingSources[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF70B4C8).withValues(alpha: 0.3),
                      child: Icon(source.type.icon, color: const Color(0xFF005B7F)),
                    ),
                    title: Text(
                      source.providerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(source.type.label),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '\$${source.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                          onPressed: () => _showFundingSourceDialog(existingItem: source),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          onPressed: () => _deleteSource(source.id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 32),

          // Save & Return Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF005B7F),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: () {
              // Return configured list back to Preparation Page
              Navigator.pop(context, {
                'isConfigured': _fundingSources.isNotEmpty,
                'totalAmount': _totalCommitted,
                'sources': _fundingSources,
              });
            },
            child: const Text('Save Funding Configuration', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}