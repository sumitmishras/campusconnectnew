import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../widgets/student_card.dart';
import '../../../core/providers/user_provider.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Discover',
          style: theme.textTheme.displayMedium?.copyWith(fontSize: 24),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.slidersHorizontal),
            onPressed: () {
              // Show advanced filters bottom sheet
              _showFiltersBottomSheet(context, theme, userProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              // Search Bar
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => userProvider.searchStudents(val),
                  decoration: InputDecoration(
                    hintText: 'Search by name, department, or interests...',
                    prefixIcon: const Icon(LucideIcons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              
              // Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All', true, theme),
                    _buildFilterChip('Recently Active', false, theme),
                    _buildFilterChip('Same Department', false, theme),
                    _buildFilterChip('Same Year', false, theme),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Students List
              Expanded(
                child: userProvider.isLoading 
                  ? const Center(child: CircularProgressIndicator())
                  : userProvider.students.isEmpty
                    ? Center(child: Text('No students found.', style: theme.textTheme.bodyLarge))
                    : ListView.builder(
                        itemCount: userProvider.students.length,
                        itemBuilder: (context, index) {
                          return StudentCard(student: userProvider.students[index]);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (bool selected) {},
        selectedColor: theme.primaryColor.withOpacity(0.1),
        checkmarkColor: theme.primaryColor,
        labelStyle: TextStyle(
          color: isSelected ? theme.primaryColor : theme.textTheme.bodyMedium?.color,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? theme.primaryColor : theme.dividerColor,
          ),
        ),
      ),
    );
  }

  void _showFiltersBottomSheet(BuildContext context, ThemeData theme, UserProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Advanced Filters', style: theme.textTheme.titleLarge),
              const SizedBox(height: 24),
              // Dummy filters
              Text('Department', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(label: const Text('Any'), selected: true, onSelected: (v) => provider.filterByDepartment('Any')),
                  ChoiceChip(label: const Text('Computer Science'), selected: false, onSelected: (v) => provider.filterByDepartment('Computer Science')),
                  ChoiceChip(label: const Text('MBA'), selected: false, onSelected: (v) => provider.filterByDepartment('MBA')),
                  ChoiceChip(label: const Text('BCA'), selected: false, onSelected: (v) => provider.filterByDepartment('BCA')),
                ],
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Apply Filters'),
              ),
            ],
          ),
        );
      },
    );
  }
}
