import 'package:flutter/material.dart';

// Import our standalone page widgets
import 'src/pages/dashboardPage.dart';
import 'src/pages/projects/list.dart';
import 'src/pages/settingsPage.dart';

void main() {
  runApp(
    const MaterialApp(
      home: Shell()
    ),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});

 @override
 State<Shell> createState() => _ShellState(); 
}

// This class holds the "state" (data that changes over time)
class _ShellState extends State<Shell>{

  // Track which menu item is selected (0 = Dashboard, 1 = Projects, 2 = Settings)
  int _selectedIndex = 0;

  // A list of our different page widgets
  final List<Widget> _pages = [
    const DashboardPage(),
    const ProjectsPage(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Project Manager'),
        foregroundColor: Colors.greenAccent,
      ),

      drawer: Drawer(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero, // Removes rounded corners entirely
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.greenAccent),
              child: Text(
                'Menu',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard),
              title: const Text('Dashboard'),
              onTap: () {
                // setState tells Flutter: "The variable changed, re-draw the screen!"
                setState(() {
                  _selectedIndex = 0;
                });
                Navigator.pop(context); // Close the drawer menu
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Projects'),
              onTap: () {
                setState(() {
                  _selectedIndex = 1;
                });
                Navigator.pop(context); // Close the drawer menu
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                setState(() {
                  _selectedIndex = 2;
                });
                Navigator.pop(context); // Close the drawer menu
              },
            ),
          ],
        ),
      ),
      // Display whichever page matches the currently selected index
      body: _pages[_selectedIndex],
    );
  }

}
