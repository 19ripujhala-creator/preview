import 'package:shaladarpan/widgets/page_content_motion.dart';
import 'package:shaladarpan/widgets/adaptive_layout.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'monthly_tasks_screen.dart';

class MonthlyTasksHub extends StatefulWidget {
  final String schoolId;
  final void Function(String task, bool? completed)? onStatus;
  const MonthlyTasksHub({super.key, required this.schoolId, this.onStatus});
  @override
  State<MonthlyTasksHub> createState() => _MonthlyTasksHubState();
}

class _MonthlyTasksHubState extends State<MonthlyTasksHub> {
  static const _ink = Color(0xFF0F172A), _muted = Color(0xFF64748B);
  final _formKeys = [GlobalKey<MonthlyTasksScreenState>(), GlobalKey<MonthlyTasksScreenState>()];
  final Set<int> _activated = {0, 1};
  int _selected = 0;
  bool _switching = false;

  Future<void> _select(int index) async {
    if (_switching || index == _selected) return;
    _switching = true;
    try {
      final current = _formKeys[_selected].currentState;
      if (current != null && !await current.prepareTabSwitch()) return;
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() { _selected = index; _activated.add(index); });
    } finally { _switching = false; }
  }

  Widget _tab(int index, String label) {
    final selected = _selected == index;
    return Expanded(child: Material(color: selected ? _ink : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? _ink : const Color(0xFFE2E8F0))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => _select(index), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(label, textAlign: TextAlign.center, maxLines: 1,
          style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : _muted)),
      )),
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(backgroundColor: const Color(0xFFF8FAFC), surfaceTintColor: Colors.transparent,
      title: const Text('Monthly Tasks', style: TextStyle(fontFamily: 'PlusJakartaSans',
        fontSize: 17, fontWeight: FontWeight.w600, color: _ink)),
      actions: [IconButton(tooltip: 'Refresh selected form',
        onPressed: _switching ? null : () => _formKeys[_selected].currentState?.refreshForm(),
        icon: const Icon(CupertinoIcons.arrow_clockwise, size: 18, color: _ink))]),
    body: PageContentMotion(child: Column(children: [
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppAdaptive.contentWidth(MediaQuery.sizeOf(context).width)),
        child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(children: [
            _tab(0, 'District Ranking'), const SizedBox(width: 8), _tab(1, 'VIFFS Tablet Entry'),
          ])),
      )),
      Expanded(child: IndexedStack(index: _selected, children: [
        for (var index = 0; index < 2; index++)
          _activated.contains(index)
              ? index == 0 ? DistrictRankingScreen(
                  key: _formKeys[0], schoolId: widget.schoolId, embedded: true,
                  active: _selected == 0, onStatus: widget.onStatus)
                : ViffsTabletEntryScreen(
                  key: _formKeys[1], schoolId: widget.schoolId, embedded: true,
                  active: _selected == 1, onStatus: widget.onStatus)
              : const SizedBox.shrink(),
      ])),
    ])),
  );
}
