import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../projects/project_store.dart';
import '../../application/search_providers.dart';
import '../../domain/search_models.dart';

class SearchFilterBar extends ConsumerStatefulWidget {
  const SearchFilterBar({
    required this.filters,
    required this.onChanged,
    super.key,
  });

  final SearchFilters filters;
  final ValueChanged<SearchFilters> onChanged;

  @override
  ConsumerState<SearchFilterBar> createState() => _SearchFilterBarState();
}

class _SearchFilterBarState extends ConsumerState<SearchFilterBar> {
  final _tagController = TextEditingController();
  var _expanded = false;

  static const _recordTypeLabels = <String, String>{
    'memo': '备忘',
    'long_note': '长文',
    'todo': '待办',
    'expense': '消费',
    'focus': '专注',
    'body': '身体',
    'moment_photo': '照片',
    'voice_memo': '语音',
  };

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectSearchSummariesProvider);
    final recordTypes = ref.watch(searchRecordTypesProvider);
    final availableRecordTypes = {
      ...?recordTypes.value,
      ...widget.filters.recordTypes,
    }.toList()..sort();
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<SearchScope>(
                    key: const ValueKey('search-scope-control'),
                    segments: const [
                      ButtonSegment(value: SearchScope.all, label: Text('全部')),
                      ButtonSegment(
                        value: SearchScope.records,
                        label: Text('记录'),
                      ),
                      ButtonSegment(
                        value: SearchScope.projects,
                        label: Text('项目'),
                      ),
                    ],
                    selected: {widget.filters.scope},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      widget.onChanged(
                        widget.filters.copyWith(scope: selection.single),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  button: true,
                  label: _expanded ? '收起搜索筛选' : '展开搜索筛选',
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: IconButton(
                      key: const ValueKey('search-filter-toggle'),
                      tooltip: _expanded ? '收起筛选' : '展开筛选',
                      onPressed: () => setState(() => _expanded = !_expanded),
                      icon: Badge(
                        isLabelVisible: _activeFilterCount > 0,
                        label: Text('$_activeFilterCount'),
                        child: Icon(
                          _expanded ? Icons.tune_rounded : Icons.tune_outlined,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: _expanded
                  ? ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * 0.48,
                      ),
                      child: SingleChildScrollView(
                        key: const ValueKey('search-filter-scroll'),
                        padding: const EdgeInsets.only(
                          top: AppSpacing.md,
                          right: AppSpacing.xs,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _FilterLabel(text: '时间'),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                ChoiceChip(
                                  label: const Text('全部时间'),
                                  selected:
                                      widget.filters.fromDate == null &&
                                      widget.filters.toDate == null,
                                  onSelected: (_) => widget.onChanged(
                                    widget.filters.copyWith(
                                      clearFromDate: true,
                                      clearToDate: true,
                                    ),
                                  ),
                                ),
                                ChoiceChip(
                                  label: const Text('近 7 天'),
                                  selected: _isRecentDays(7),
                                  onSelected: (_) => _setRecentDays(7),
                                ),
                                ChoiceChip(
                                  label: const Text('近 30 天'),
                                  selected: _isRecentDays(30),
                                  onSelected: (_) => _setRecentDays(30),
                                ),
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.date_range_rounded,
                                    size: 18,
                                  ),
                                  label: Text(_customDateLabel),
                                  onPressed: _chooseDateRange,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _FilterLabel(text: '类型'),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                for (final type in availableRecordTypes)
                                  FilterChip(
                                    key: ValueKey('search-record-type-$type'),
                                    label: Text(
                                      _recordTypeLabels[type] ?? type,
                                    ),
                                    selected: widget.filters.recordTypes
                                        .contains(type),
                                    onSelected: (selected) =>
                                        _toggleRecordType(type, selected),
                                  ),
                                if (recordTypes.isLoading)
                                  const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                if (recordTypes.hasError)
                                  Text(
                                    '记录类型加载失败',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _FilterLabel(text: '项目'),
                            const SizedBox(height: AppSpacing.xs),
                            DropdownMenu<String>(
                              key: const ValueKey('search-project-filter'),
                              width: double.infinity,
                              initialSelection: widget.filters.projectId ?? '',
                              leadingIcon: const Icon(Icons.flag_outlined),
                              label: const Text('关联项目'),
                              onSelected: (value) => widget.onChanged(
                                widget.filters.copyWith(
                                  projectId: value,
                                  clearProjectId:
                                      value == null || value.isEmpty,
                                ),
                              ),
                              dropdownMenuEntries: [
                                const DropdownMenuEntry(
                                  value: '',
                                  label: '全部项目',
                                ),
                                ...?projects.value?.map(
                                  (project) => DropdownMenuEntry(
                                    value: project.id,
                                    label: project.status == '归档'
                                        ? '${project.name} · 归档'
                                        : project.name,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _FilterLabel(text: '标签'),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey('search-tag-input'),
                                    controller: _tagController,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _addTag(),
                                    decoration: const InputDecoration(
                                      hintText: '标签名称',
                                      prefixIcon: Icon(Icons.tag_rounded),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: IconButton(
                                    tooltip: '添加标签筛选',
                                    onPressed: _addTag,
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ),
                              ],
                            ),
                            if (widget.filters.tags.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Wrap(
                                spacing: AppSpacing.xs,
                                children: [
                                  for (final tag in widget.filters.tags)
                                    InputChip(
                                      label: Text('#$tag'),
                                      onDeleted: () => _removeTag(tag),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  int get _activeFilterCount {
    var count = 0;
    if (widget.filters.fromDate != null || widget.filters.toDate != null) {
      count++;
    }
    if (widget.filters.recordTypes.isNotEmpty) count++;
    if (widget.filters.projectId != null) count++;
    if (widget.filters.tags.isNotEmpty) count++;
    return count;
  }

  bool _isRecentDays(int days) {
    final from = widget.filters.fromDate;
    final to = widget.filters.toDate;
    if (from == null || to == null) return false;
    final today = _dateOnly(DateTime.now());
    return _sameDay(to, today) &&
        _sameDay(from, today.subtract(Duration(days: days - 1)));
  }

  void _setRecentDays(int days) {
    final today = _dateOnly(DateTime.now());
    widget.onChanged(
      widget.filters.copyWith(
        fromDate: today.subtract(Duration(days: days - 1)),
        toDate: today,
      ),
    );
  }

  String get _customDateLabel {
    final from = widget.filters.fromDate;
    final to = widget.filters.toDate;
    if (from == null || to == null || _isRecentDays(7) || _isRecentDays(30)) {
      return '自定义';
    }
    return '${from.month}/${from.day} - ${to.month}/${to.day}';
  }

  Future<void> _chooseDateRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          widget.filters.fromDate != null && widget.filters.toDate != null
          ? DateTimeRange(
              start: widget.filters.fromDate!,
              end: widget.filters.toDate!,
            )
          : null,
    );
    if (range == null) return;
    widget.onChanged(
      widget.filters.copyWith(fromDate: range.start, toDate: range.end),
    );
  }

  void _toggleRecordType(String type, bool selected) {
    final types = {...widget.filters.recordTypes};
    selected ? types.add(type) : types.remove(type);
    widget.onChanged(widget.filters.copyWith(recordTypes: types));
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isEmpty) return;
    widget.onChanged(
      widget.filters.copyWith(tags: {...widget.filters.tags, tag}),
    );
    _tagController.clear();
  }

  void _removeTag(String tag) {
    widget.onChanged(
      widget.filters.copyWith(tags: {...widget.filters.tags}..remove(tag)),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;
