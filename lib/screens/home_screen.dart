import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'test_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  String _selectedPerson = '영욱';
  Map<String, Map<String, List<Map<String, String>>>> _wordsByDate = {};

  static const _blue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF1E88E5);
  static const _persons = ['영욱', '준형'];

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  final _db = FirebaseFirestore.instance;
  bool _isSaving = false;

  Future<void> _loadWords() async {
    final snapshot = await _db.collection('words').get();
    final map = <String, Map<String, List<Map<String, String>>>>{};
    for (final doc in snapshot.docs) {
      try {
        final personMap = <String, List<Map<String, String>>>{};
        doc.data().forEach((person, entries) {
          if (entries is List) {
            personMap[person] = entries
                .whereType<Map>()
                .map((e) => Map<String, String>.from(
                      e.map((k, v) => MapEntry(k.toString(), v.toString())),
                    ))
                .toList();
          }
        });
        if (personMap.isNotEmpty) map[doc.id] = personMap;
      } catch (_) {}
    }
    setState(() => _wordsByDate = map);
  }

  Future<void> _saveToFirestore(BuildContext context) async {
    final key = _dateKey(_selectedDay);
    setState(() => _isSaving = true);
    try {
      final ref = _db.collection('words').doc(key);
      final dateData = _wordsByDate[key];
      if (dateData == null || dateData.isEmpty) {
        await ref.delete();
      } else {
        await ref.set(dateData);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('저장됐어요!'),
            backgroundColor: Color(0xFF2E7D32),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('저장 실패: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _onEntriesChanged(List<Map<String, String>> entries) {
    final key = _dateKey(_selectedDay);
    setState(() {
      if (entries.isEmpty) {
        _wordsByDate[key]?.remove(_selectedPerson);
        if (_wordsByDate[key]?.isEmpty ?? false) _wordsByDate.remove(key);
      } else {
        _wordsByDate[key] ??= {};
        _wordsByDate[key]![_selectedPerson] = entries;
      }
    });
  }

  bool _hasWordsOnDay(DateTime day) {
    final list = _wordsByDate[_dateKey(day)]?[_selectedPerson];
    return list != null && list.isNotEmpty;
  }

  List<Map<String, String>> _entriesForSelected() =>
      _wordsByDate[_dateKey(_selectedDay)]?[_selectedPerson] ?? [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(
          children: [
            // 상단 영욱 / 준형 버튼
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_blue, _lightBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Row(
                children: _persons.map((p) {
                  final isSelected = _selectedPerson == p;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: p == '영욱' ? 8 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedPerson = p),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Text(
                            p,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? _blue : Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 달력
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.07),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: TableCalendar(
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2030, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              isSameDay(_selectedDay, day),
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = selectedDay;
                              _focusedDay = focusedDay;
                            });
                          },
                          eventLoader: (day) => _hasWordsOnDay(day) ? [1] : [],
                          calendarStyle: CalendarStyle(
                            todayDecoration: BoxDecoration(
                              color: _lightBlue.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                            todayTextStyle: const TextStyle(
                              color: _blue,
                              fontWeight: FontWeight.bold,
                            ),
                            selectedDecoration: const BoxDecoration(
                              color: _blue,
                              shape: BoxShape.circle,
                            ),
                            selectedTextStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            markerDecoration: const BoxDecoration(
                              color: _lightBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          headerStyle: const HeaderStyle(
                            formatButtonVisible: false,
                            titleCentered: true,
                            titleTextStyle: TextStyle(
                              color: Colors.black87,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                            leftChevronIcon:
                                Icon(Icons.chevron_left, color: Colors.black54),
                            rightChevronIcon: Icon(Icons.chevron_right,
                                color: Colors.black54),
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(color: Colors.black54),
                            weekendStyle: TextStyle(color: Colors.black54),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 인라인 단어 편집기
                    _DayEditor(
                      key: ValueKey('${_dateKey(_selectedDay)}_$_selectedPerson'),
                      day: _selectedDay,
                      person: _selectedPerson,
                      initialEntries: _entriesForSelected(),
                      onChanged: _onEntriesChanged,
                    ),

                    // 저장 버튼
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : () => _saveToFirestore(context),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _isSaving ? '저장 중...' : '저장',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF43A047),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    // 테스트 버튼
                    if (_entriesForSelected()
                        .any((e) => e['word']!.isNotEmpty && e['meaning']!.isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TestScreen(
                                day: _selectedDay,
                                person: _selectedPerson,
                                entries: _entriesForSelected(),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.quiz_outlined),
                          label: const Text(
                            '테스트 시작',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayEditor extends StatefulWidget {
  final DateTime day;
  final String person;
  final List<Map<String, String>> initialEntries;
  final void Function(List<Map<String, String>>) onChanged;

  const _DayEditor({
    super.key,
    required this.day,
    required this.person,
    required this.initialEntries,
    required this.onChanged,
  });

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late List<TextEditingController> _wordCtrls;
  late List<TextEditingController> _meaningCtrls;
  late List<FocusNode> _wordNodes;
  late List<FocusNode> _meaningNodes;

  static const _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _wordCtrls = widget.initialEntries
        .map((e) => TextEditingController(text: e['word'] ?? ''))
        .toList();
    _meaningCtrls = widget.initialEntries
        .map((e) => TextEditingController(text: e['meaning'] ?? ''))
        .toList();
    _wordNodes = List.generate(widget.initialEntries.length, (_) => FocusNode());
    _meaningNodes = List.generate(widget.initialEntries.length, (_) => FocusNode());
    _addEmptyRow();
  }

  @override
  void dispose() {
    for (final c in _wordCtrls) c.dispose();
    for (final c in _meaningCtrls) c.dispose();
    for (final n in _wordNodes) n.dispose();
    for (final n in _meaningNodes) n.dispose();
    super.dispose();
  }

  void _addEmptyRow() {
    _wordCtrls.add(TextEditingController());
    _meaningCtrls.add(TextEditingController());
    _wordNodes.add(FocusNode());
    _meaningNodes.add(FocusNode());
  }

  void _onChanged(int index) {
    final isLast = index == _wordCtrls.length - 1;
    final hasContent = _wordCtrls[index].text.isNotEmpty ||
        _meaningCtrls[index].text.isNotEmpty;
    if (isLast && hasContent) {
      setState(() => _addEmptyRow());
    }
    final entries = List.generate(_wordCtrls.length, (i) => {
          'word': _wordCtrls[i].text.trim(),
          'meaning': _meaningCtrls[i].text.trim(),
        })
        .where((e) => e['word']!.isNotEmpty || e['meaning']!.isNotEmpty)
        .toList();
    widget.onChanged(entries);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              '${widget.day.month}월 ${widget.day.day}일 · ${widget.person}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _blue,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 컬럼 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '단어 및 문장',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: Colors.transparent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '뜻',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // 단어 / 뜻 입력 행
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: _wordCtrls.length,
            itemBuilder: (_, i) {
              final isEmpty = _wordCtrls[i].text.isEmpty &&
                  _meaningCtrls[i].text.isEmpty;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 번호
                  SizedBox(
                    width: 32,
                    child: Text(
                      '${i + 1}.',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: isEmpty ? Colors.grey.shade300 : _blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 단어 입력
                  Expanded(
                    child: TextField(
                      controller: _wordCtrls[i],
                      focusNode: _wordNodes[i],
                      onChanged: (_) => setState(() => _onChanged(i)),
                      onSubmitted: (_) => _meaningNodes[i].requestFocus(),
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: i == 0 ? '단어 및 문장' : '',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  // 구분선
                  Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    color: Colors.grey.shade300,
                  ),
                  // 뜻 입력
                  Expanded(
                    child: TextField(
                      controller: _meaningCtrls[i],
                      focusNode: _meaningNodes[i],
                      onChanged: (_) => setState(() => _onChanged(i)),
                      onSubmitted: (_) {
                        if (i + 1 < _wordNodes.length) {
                          _wordNodes[i + 1].requestFocus();
                        }
                      },
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: i == 0 ? '뜻' : '',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
