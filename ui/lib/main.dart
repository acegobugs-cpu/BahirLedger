import 'package:flutter/material.dart';

import 'src/app.dart';
export 'src/app.dart' show BahirLedgerApp;

// Import our standalone page widgets
import 'src/pages/projects/list.dart';

void main() {
  runApp(BahirLedgerApp(demoBuilder: (_) => const Shell()));
}

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

// This class holds the "state" (data that changes over time)
class _ShellState extends State<Shell> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8), // Rounded corners
            child: Image.asset('assets/ph.jpg', fit: BoxFit.cover),
          ),
        ),
        title: const Text(
          'Project Manager',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        foregroundColor: Color(0xFF2A819E),
      ),

      // Display whichever page matches the currently selected index
      body: const ProjectsPage(),
    );
  }
}
