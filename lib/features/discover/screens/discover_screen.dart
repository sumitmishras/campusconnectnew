import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/data/reference_data.dart';
import '../../../core/models/discover_query.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/user_provider.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/custom_button.dart';
import '../widgets/student_card.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  /// How close to the bottom the list gets before the next page is asked for.
  /// Roughly two cards, so the spinner is rarely the thing the student is
  /// looking at.
  static const _loadMoreThreshold = 400.0;

  static const _quickFilters = <DiscoverFilter, String>{
    DiscoverFilter.all: 'All',
    DiscoverFilter.online: 'Online now',
    DiscoverFilter.recentlyActive: 'Recently Active',
    DiscoverFilter.sameDepartment: 'Same Department',
    DiscoverFilter.sameYear: 'Same Year',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - _loadMoreThreshold) return;
    // loadMore() is a no-op unless there is another page and nothing is
    // already in flight, so calling it on every frame near the bottom is safe.
    context.read<UserProvider>().loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.watch<UserProvider>();
    final students = userProvider.students;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        centerTitle: false,
        title: Text('Discover', style: theme.textTheme.displaySmall),
        actions: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.slidersHorizontal),
                tooltip: 'Advanced filters',
                onPressed: () => _showFiltersSheet(context, userProvider),
              ),
              if (userProvider.activeFilterCount > 0)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: theme.primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                // The provider debounces; the field itself stays instant
                // because the controller, not a rebuild, drives the text.
                onChanged: userProvider.searchStudents,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by name, department, or interests...',
                  prefixIcon: const Icon(LucideIcons.search, size: 20),
                  // Rebuilds only the clear button when the text changes,
                  // rather than the whole screen on every keystroke.
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(LucideIcons.x, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          userProvider.searchStudents('');
                        },
                      );
                    },
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: _quickFilters.entries.map((entry) {
                  final isSelected = userProvider.quickFilter == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(entry.value),
                      selected: isSelected,
                      showCheckmark: false,
                      onSelected: (_) => userProvider.setQuickFilter(entry.key),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? theme.primaryColor
                            : theme.textTheme.bodyMedium?.color,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color:
                            isSelected ? theme.primaryColor : theme.dividerColor,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (userProvider.activeFilterCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Icon(LucideIcons.listFilter,
                        size: 14, color: theme.primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      '${userProvider.activeFilterCount} filter${userProvider.activeFilterCount > 1 ? 's' : ''} applied',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.primaryColor),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: userProvider.clearFilters,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Expanded(child: _buildBody(theme, userProvider, students)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      ThemeData theme, UserProvider userProvider, List<User> students) {
    if (userProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // A failed load with nothing to fall back on. The list keeps its contents
    // when a *later* page fails, so this only fires on a cold failure.
    if (userProvider.error != null && students.isEmpty) {
      return EmptyState(
        icon: LucideIcons.wifiOff,
        title: 'Could not load students',
        message: userProvider.error!,
        actionLabel: 'Try again',
        onAction: userProvider.retry,
      );
    }

    if (students.isEmpty) {
      return EmptyState(
        icon: LucideIcons.search,
        title: 'No students found',
        message:
            'Try a different search term or clear the filters you have applied.',
        actionLabel: 'Clear filters',
        onAction: () {
          _searchController.clear();
          userProvider.clearSearchAndFilters();
        },
      );
    }

    final showFooter = userProvider.isLoadingMore || userProvider.error != null;

    return RefreshIndicator(
      onRefresh: userProvider.refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: students.length + 1 + (showFooter ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${students.length} students match',
                style: theme.textTheme.bodySmall,
              ),
            );
          }
          if (index <= students.length) {
            return StudentCard(student: students[index - 1]);
          }
          return _buildFooter(theme, userProvider);
        },
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, UserProvider userProvider) {
    if (userProvider.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    // Only reachable when a "load more" failed — the first-page failure is
    // handled above, with the whole screen.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Text(
            userProvider.error ?? '',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: userProvider.loadMore,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }

  void _showFiltersSheet(BuildContext context, UserProvider provider) {
    var department = provider.departmentFilter;
    var year = provider.yearFilter;
    var gender = provider.genderFilter;
    var lookingFor = provider.lookingForFilter;
    final interests = provider.interestFilters.toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (builderContext, setSheetState) {
            Widget group(String title, List<String> options, String current,
                ValueChanged<String> onPick) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [DiscoverQuery.any, ...options].map((o) {
                      final selected = current == o;
                      return ChoiceChip(
                        label: Text(o),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => setSheetState(() => onPick(o)),
                        labelStyle: TextStyle(
                          color: selected
                              ? theme.primaryColor
                              : theme.textTheme.bodyMedium?.color,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color:
                              selected ? theme.primaryColor : theme.dividerColor,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }

            // Interests are multi-select — a student looking for people who
            // code *or* play football wants both, and the repository does an
            // array overlap rather than a containment.
            Widget multiGroup(
                String title, List<String> options, Set<String> selection) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((o) {
                      final selected = selection.contains(o);
                      return FilterChip(
                        label: Text(o),
                        selected: selected,
                        showCheckmark: false,
                        onSelected: (_) => setSheetState(() {
                          if (selected) {
                            selection.remove(o);
                          } else {
                            selection.add(o);
                          }
                        }),
                        labelStyle: TextStyle(
                          color: selected
                              ? theme.primaryColor
                              : theme.textTheme.bodyMedium?.color,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color:
                              selected ? theme.primaryColor : theme.dividerColor,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.75,
              maxChildSize: 0.92,
              builder: (context, scrollController) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SheetHandle(),
                    Row(
                      children: [
                        Text('Advanced Filters',
                            style: theme.textTheme.titleLarge),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setSheetState(() {
                            department = DiscoverQuery.any;
                            year = DiscoverQuery.any;
                            gender = DiscoverQuery.any;
                            lookingFor = DiscoverQuery.any;
                            interests.clear();
                          }),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView(
                        controller: scrollController,
                        children: [
                          group('Department', ReferenceData.departments,
                              department, (v) => department = v),
                          group('Year', ReferenceData.years, year,
                              (v) => year = v),
                          group('Gender', _genderOptions, gender,
                              (v) => gender = v),
                          group('Looking For', ReferenceData.purposes,
                              lookingFor, (v) => lookingFor = v),
                          multiGroup('Interests',
                              ReferenceData.interests, interests),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    CustomButton(
                      text: 'Apply Filters',
                      onPressed: () {
                        provider.applyAdvancedFilters(
                          department: department,
                          year: year,
                          gender: gender,
                          lookingFor: lookingFor,
                          interests: interests.toList(),
                        );
                        Navigator.pop(sheetContext);
                        showAppSnackBar(this.context, 'Filters applied',
                            icon: LucideIcons.listFilter);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Matches the values the registration wizard writes into `profiles.gender`.
  static const _genderOptions = ['Male', 'Female', 'Other'];
}
