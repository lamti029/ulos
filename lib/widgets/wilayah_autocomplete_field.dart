import 'dart:async';
import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

/// A reusable searchable dropdown widget for selecting wilayah items
/// (kabupaten, kecamatan, desa) by name while storing the code.
class WilayahAutocompleteField extends StatefulWidget {
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextEditingController? controller;
  final TextEditingController? displayController;
  final Future<List<Map<String, dynamic>>> Function(String query) fetchItems;
  final String codeKey;
  final String nameKey;
  final bool enabled;
  final void Function(String code, String name)? onSelected;

  const WilayahAutocompleteField({
    super.key,
    required this.label,
    required this.icon,
    this.validator,
    this.controller,
    this.displayController,
    required this.fetchItems,
    required this.codeKey,
    required this.nameKey,
    this.enabled = true,
    this.onSelected,
  });

  @override
  State<WilayahAutocompleteField> createState() =>
      _WilayahAutocompleteFieldState();
}

class _WilayahAutocompleteFieldState extends State<WilayahAutocompleteField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _openSelector() async {
    if (!widget.enabled) return;

    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _WilayahSelectorBottomSheet(
        label: widget.label,
        fetchItems: widget.fetchItems,
        codeKey: widget.codeKey,
        nameKey: widget.nameKey,
      ),
    );

    if (result != null) {
      final code = result[widget.codeKey] as String;
      final name = result[widget.nameKey] as String;
      widget.controller?.text = code;
      widget.displayController?.text = name;
      widget.onSelected?.call(code, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayText = widget.displayController?.text ?? '';
    final hasValue = displayText.isNotEmpty;

    return TextFormField(
      controller: widget.displayController,
      enabled: widget.enabled,
      readOnly: true,
      onTap: _openSelector,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.enabled
            ? 'Tap to search ${widget.label}'
            : 'Select parent first',
        prefixIcon: Icon(widget.icon, color: AppColors.primary),
        suffixIcon: hasValue
            ? IconButton(
                icon: const Icon(Icons.clear, color: AppColors.textSecondary),
                onPressed: widget.enabled
                    ? () {
                        widget.controller?.clear();
                        widget.displayController?.clear();
                        widget.onSelected?.call('', '');
                      }
                    : null,
              )
            : const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
      ),
      validator: widget.validator,
    );
  }
}

/// Bottom sheet that allows searching and selecting a wilayah item.
class _WilayahSelectorBottomSheet extends StatefulWidget {
  final String label;
  final Future<List<Map<String, dynamic>>> Function(String query) fetchItems;
  final String codeKey;
  final String nameKey;

  const _WilayahSelectorBottomSheet({
    required this.label,
    required this.fetchItems,
    required this.codeKey,
    required this.nameKey,
  });

  @override
  State<_WilayahSelectorBottomSheet> createState() =>
      _WilayahSelectorBottomSheetState();
}

class _WilayahSelectorBottomSheetState
    extends State<_WilayahSelectorBottomSheet> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _allItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  bool _isLoading = false;
  String? _error;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await widget.fetchItems('');
      if (mounted) {
        setState(() {
          _allItems = items;
          _filteredItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final query = _searchController.text.toLowerCase();
      setState(() {
        if (query.isEmpty) {
          _filteredItems = _allItems;
        } else {
          _filteredItems = _allItems.where((item) {
            final name = (item[widget.nameKey] as String? ?? '').toLowerCase();
            return name.contains(query);
          }).toList();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                'Select ${widget.label}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              // Search field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  decoration: InputDecoration(
                    hintText: 'Search ${widget.label}...',
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.primary,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Results
              Flexible(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: 8),
              Text(
                'Failed to load data',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadItems, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No results found',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _filteredItems.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final name = item[widget.nameKey] as String? ?? '';
        final code = item[widget.codeKey] as String? ?? '';
        return ListTile(
          title: Text(name),
          subtitle: Text(
            code,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          leading: const Icon(
            Icons.location_on_outlined,
            color: AppColors.primary,
          ),
          onTap: () => Navigator.of(context).pop(item),
        );
      },
    );
  }
}
