import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/brand_colors.dart';

class CompactDateRangePicker extends StatefulWidget {
  final DateTime initialStart;
  final DateTime initialEnd;
  final DateTime firstDate;

  const CompactDateRangePicker({
    super.key,
    required this.initialStart,
    required this.initialEnd,
    required this.firstDate,
  });

  @override
  State<CompactDateRangePicker> createState() =>
      _CompactDateRangePickerState();
}

class _CompactDateRangePickerState extends State<CompactDateRangePicker> {
  late DateTime _displayMonth;
  late DateTime _start;
  DateTime? _end;
  bool _pickingEnd = false;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _displayMonth = DateTime(_start.year, _start.month);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime day) {
    setState(() {
      if (!_pickingEnd) {
        _start = day;
        _end = null;
        _pickingEnd = true;
      } else {
        if (!day.isBefore(_start)) {
          _end = day;
          _pickingEnd = false;
        } else {
          _start = day;
          _end = null;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bothSet = _end != null;
    final hintText = _pickingEnd
        ? '${DateFormat('d MMM').format(_start)} → select end date'
        : bothSet
            ? '${DateFormat('d MMM').format(_start)} – ${DateFormat('d MMM').format(_end!)}'
            : 'Tap to select start date';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => setState(() {
                      _displayMonth = DateTime(
                          _displayMonth.year, _displayMonth.month - 1);
                    }),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_displayMonth),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => setState(() {
                      _displayMonth = DateTime(
                          _displayMonth.year, _displayMonth.month + 1);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    .map((h) => Expanded(
                          child: Center(
                            child: Text(
                              h,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
              _buildGrid(),
              const SizedBox(height: 8),
              Text(
                hintText,
                style: TextStyle(
                  fontSize: 13,
                  color: bothSet ? BrandColors.deepBlue : Colors.black45,
                  fontWeight:
                      bothSet ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: TextButton.styleFrom(
                        foregroundColor: BrandColors.charcoal),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: bothSet
                        ? () => Navigator.of(context)
                            .pop(DateTimeRange(start: _start, end: _end!))
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BrandColors.deepBlue,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.black12,
                    ),
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrid() {
    final year = _displayMonth.year;
    final month = _displayMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final leadingBlanks = DateTime(year, month, 1).weekday - 1;

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        for (int i = 0; i < leadingBlanks; i++) const SizedBox(),
        for (int d = 1; d <= daysInMonth; d++)
          _buildCell(DateTime(year, month, d)),
      ],
    );
  }

  Widget _buildCell(DateTime day) {
    final disabled = day.isBefore(widget.firstDate);
    final isStart = _isSameDay(day, _start);
    final isEnd = _end != null && _isSameDay(day, _end!);
    final singleDay = _end != null && _isSameDay(_start, _end!);
    final inRange =
        _end != null && day.isAfter(_start) && day.isBefore(_end!);

    return GestureDetector(
      onTap: disabled ? null : () => _onDayTap(day),
      child: MouseRegion(
        cursor:
            disabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
        child: LayoutBuilder(
          builder: (_, box) {
            final sz = box.maxWidth;
            final rangeColor =
                BrandColors.deepBlue.withValues(alpha: 0.12);
            final vPad = sz * 0.18;

            return Stack(
              alignment: Alignment.center,
              children: [
                if (inRange)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: vPad,
                    bottom: vPad,
                    child: ColoredBox(color: rangeColor),
                  ),
                if (isStart && _end != null && !singleDay)
                  Positioned(
                    left: sz / 2,
                    right: 0,
                    top: vPad,
                    bottom: vPad,
                    child: ColoredBox(color: rangeColor),
                  ),
                if (isEnd && !singleDay)
                  Positioned(
                    left: 0,
                    right: sz / 2,
                    top: vPad,
                    bottom: vPad,
                    child: ColoredBox(color: rangeColor),
                  ),
                if (isStart || isEnd)
                  Container(
                    width: sz * 0.72,
                    height: sz * 0.72,
                    decoration: const BoxDecoration(
                      color: BrandColors.deepBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  '${day.day}',
                  style: TextStyle(
                    fontSize: 13,
                    color: disabled
                        ? Colors.black26
                        : (isStart || isEnd)
                            ? Colors.white
                            : inRange
                                ? BrandColors.deepBlue
                                : BrandColors.charcoal,
                    fontWeight: (isStart || isEnd)
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
