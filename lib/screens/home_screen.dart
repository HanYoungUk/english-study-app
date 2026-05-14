import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'test_screen.dart';
import 'wrong_note_screen.dart';
import 'record_screen.dart';
import 'stats_screen.dart';
import 'favorites_screen.dart';
import 'all_words_screen.dart';

const _geminiKey = String.fromEnvironment('GEMINI_KEY');
const _geminiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiKey';

List<Map<String, String>> _parseWordEntries(String text) {
  final results = <Map<String, String>>[];
  final numPrefix = RegExp(r'^\d+\.\s*');
  final parenFormat = RegExp(r'^(.+?)\s*[（(]([^)）]+)[）)]');
  final leadingParen = RegExp(r'^\([^)）]+\)\s+');

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final stripped = line.replaceFirst(numPrefix, '').trim();
    if (stripped.isEmpty) continue;
    String word = '';
    String meaning = '';
    if (stripped.contains(' : ')) {
      final idx = stripped.indexOf(' : ');
      word = stripped.substring(0, idx).trim();
      final full = stripped.substring(idx + 3).trim();
      meaning = full.replaceFirst(leadingParen, '').trim();
      if (meaning.isEmpty) meaning = full;
    } else {
      final m = parenFormat.firstMatch(stripped);
      if (m != null) {
        word = m.group(1)!.trim();
        meaning = m.group(2)!.trim();
      }
    }
    if (word.isNotEmpty && meaning.isNotEmpty) {
      results.add({'word': word, 'meaning': meaning});
    }
  }
  return results;
}

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
  static const _displayNames = {
    '영욱': '영욱',
    '준형': '내기 매일 지는 준형이형',
  };

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _loadWords();
  }

  final _db = FirebaseFirestore.instance;
  final _tts = FlutterTts();
  bool _isSaving = false;
  int _editorRefreshKey = 0;

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

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

  Future<void> _saveWrongWords(
      String person, List<Map<String, String>> wrongs) async {
    final col =
        _db.collection('wrong_notes').doc(person).collection('words');
    for (final w in wrongs) {
      final word = w['word']!;
      if (word.isEmpty) continue;
      final existing = await col.where('word', isEqualTo: word).get();
      if (existing.docs.isEmpty) {
        await col.add({'word': word, 'meaning': w['meaning']!});
      }
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

  void _showAiSuggestions(BuildContext context) {
    final allExisting = <Map<String, String>>[];
    for (final dateMap in _wordsByDate.values) {
      final entries = dateMap[_selectedPerson];
      if (entries != null) allExisting.addAll(entries);
    }
    final existingSet = allExisting
        .map((e) => (e['word'] ?? '').toLowerCase().trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollCtrl) {
          // phase: 'settings' | 'loading' | 'results' | 'error'
          String phase = 'settings';
          int count = 30;
          final themeCtrl = TextEditingController();
          List<Map<String, String>> suggestions = [];
          List<bool> selected = [];
          String errorMsg = '';

          return StatefulBuilder(
            builder: (ctx, setModal) {
              Future<void> generate() async {
                setModal(() => phase = 'loading');
                final theme = themeCtrl.text.trim();
                final sampleLines = allExisting
                    .where((e) => (e['word'] ?? '').isNotEmpty)
                    .take(20)
                    .map((e) => '${e['word']} (${e['meaning']})')
                    .join('\n');
                final avoidLines = allExisting
                    .where((e) => (e['word'] ?? '').isNotEmpty)
                    .map((e) => e['word']!)
                    .join('\n');

                final themeSection = theme.isNotEmpty
                    ? '\n[요청 테마]\n$theme\n'
                    : '';
                final styleSection = sampleLines.isNotEmpty
                    ? '\n[학습 스타일 예시]\n$sampleLines\n'
                    : '';
                final avoidSection = avoidLines.isNotEmpty
                    ? '\n[이미 배운 표현 - 절대 포함하지 마세요]\n$avoidLines\n'
                    : '';

                final prompt =
                    '영어 표현 $count개를 만들어주세요.$themeSection$styleSection$avoidSection'
                    '반드시 아래 형식으로만 출력하세요 (번호, 설명 없이):\n'
                    'English sentence. (한국어 뜻)';

                try {
                  final res = await http.post(
                    Uri.parse(_geminiUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode({
                      'contents': [
                        {
                          'parts': [
                            {'text': prompt}
                          ]
                        }
                      ],
                      'generationConfig': {
                        'temperature': 0.8,
                        'maxOutputTokens': 4096
                      },
                    }),
                  );
                  if (res.statusCode == 200) {
                    final data =
                        jsonDecode(res.body) as Map<String, dynamic>;
                    final text = data['candidates']?[0]?['content']
                            ?['parts']?[0]?['text'] as String? ??
                        '';
                    final parsed = _parseWordEntries(text)
                        .where((e) => !existingSet
                            .contains(e['word']!.toLowerCase()))
                        .toList();
                    setModal(() {
                      suggestions = parsed;
                      selected = List.filled(parsed.length, true);
                      phase = 'results';
                    });
                  } else {
                    String msg = 'HTTP ${res.statusCode}';
                    try {
                      final d =
                          jsonDecode(res.body) as Map<String, dynamic>;
                      msg = d['error']?['message'] as String? ?? msg;
                    } catch (_) {}
                    setModal(() {
                      errorMsg = msg;
                      phase = 'error';
                    });
                  }
                } catch (e) {
                  setModal(() {
                    errorMsg = e.toString();
                    phase = 'error';
                  });
                }
              }

              final checkedCount =
                  selected.isEmpty ? 0 : selected.where((v) => v).length;

              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 헤더
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome,
                              color: Color(0xFF7B1FA2), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'AI 표현 추천 · $_selectedPerson',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          if (phase == 'results')
                            TextButton(
                              onPressed: () => setModal(() {
                                final allTrue = selected.every((v) => v);
                                for (int i = 0; i < selected.length; i++) {
                                  selected[i] = !allTrue;
                                }
                              }),
                              child: Text(
                                selected.every((v) => v) ? '전체 해제' : '전체 선택',
                                style: const TextStyle(
                                    color: Color(0xFF7B1FA2), fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (phase == 'results')
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${suggestions.length}개 생성됨 · 기존 ${allExisting.length}개 제외',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ),
                      ),
                    const Divider(height: 1),
                    // 본문
                    Expanded(
                      child: phase == 'settings'
                          ? ListView(
                              controller: scrollCtrl,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 20, 20, 16),
                              children: [
                                // 개수 선택
                                const Text('생성할 개수',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  children: [10, 20, 30, 50].map((n) {
                                    final sel = count == n;
                                    return GestureDetector(
                                      onTap: () =>
                                          setModal(() => count = n),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 22, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: sel
                                              ? const Color(0xFF7B1FA2)
                                              : Colors.grey.shade100,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '$n개',
                                          style: TextStyle(
                                            color: sel
                                                ? Colors.white
                                                : Colors.black87,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 24),
                                // 테마 입력
                                const Text('테마 (선택)',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 6),
                                Text(
                                  '비워두면 기존 단어와 비슷한 스타일로 생성해요',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: themeCtrl,
                                  decoration: InputDecoration(
                                    hintText: '예: 카페, 여행, 비즈니스, 감정 표현...',
                                    hintStyle: TextStyle(
                                        color: Colors.grey.shade400,
                                        fontSize: 13),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: Colors.grey.shade300),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(
                                          color: Color(0xFF7B1FA2)),
                                    ),
                                    contentPadding: const EdgeInsets.all(14),
                                  ),
                                ),
                                const SizedBox(height: 28),
                                if (allExisting.isNotEmpty)
                                  Text(
                                    '기존 단어 ${allExisting.length}개와 겹치지 않게 생성돼요',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400),
                                    textAlign: TextAlign.center,
                                  ),
                              ],
                            )
                          : phase == 'loading'
                              ? const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircularProgressIndicator(
                                          color: Color(0xFF7B1FA2)),
                                      SizedBox(height: 14),
                                      Text('AI가 표현을 생성하고 있어요...',
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                )
                              : phase == 'error'
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(24),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.error_outline,
                                                color: Colors.red.shade300,
                                                size: 40),
                                            const SizedBox(height: 12),
                                            Text(
                                              '오류가 발생했어요\n$errorMsg',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  color: Colors.grey.shade600,
                                                  fontSize: 13),
                                            ),
                                            const SizedBox(height: 16),
                                            TextButton(
                                              onPressed: () => setModal(
                                                  () => phase = 'settings'),
                                              child: const Text('다시 설정'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : suggestions.isEmpty
                                      ? Center(
                                          child: Text(
                                            '생성된 표현이 없어요',
                                            style: TextStyle(
                                                color: Colors.grey.shade400),
                                          ),
                                        )
                                      : ListView.builder(
                                          controller: scrollCtrl,
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 8, 16, 16),
                                          itemCount: suggestions.length,
                                          itemBuilder: (_, i) {
                                            final item = suggestions[i];
                                            return InkWell(
                                              onTap: () => setModal(() =>
                                                  selected[i] = !selected[i]),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    bottom: 6),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10),
                                                decoration: BoxDecoration(
                                                  color: selected[i]
                                                      ? const Color(0xFFF3E5F5)
                                                      : Colors.grey.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          10),
                                                  border: Border.all(
                                                    color: selected[i]
                                                        ? const Color(
                                                                0xFF7B1FA2)
                                                            .withValues(
                                                                alpha: 0.3)
                                                        : Colors.grey.shade200,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      selected[i]
                                                          ? Icons.check_circle
                                                          : Icons
                                                              .radio_button_unchecked,
                                                      color: selected[i]
                                                          ? const Color(
                                                              0xFF7B1FA2)
                                                          : Colors
                                                              .grey.shade300,
                                                      size: 20,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            item['word']!,
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 14,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          Text(
                                                            item['meaning']!,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: Colors.grey
                                                                  .shade600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                    ),
                    // 하단 버튼
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: SizedBox(
                          width: double.infinity,
                          child: phase == 'settings'
                              ? ElevatedButton.icon(
                                  onPressed: generate,
                                  icon: const Icon(Icons.auto_awesome,
                                      size: 18),
                                  label: Text(
                                    'AI로 $count개 생성',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF7B1FA2),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 0,
                                  ),
                                )
                              : phase == 'results'
                                  ? ElevatedButton.icon(
                                      onPressed: checkedCount == 0
                                          ? null
                                          : () {
                                              final toAdd =
                                                  <Map<String, String>>[];
                                              for (int i = 0;
                                                  i < suggestions.length;
                                                  i++) {
                                                if (selected[i]) {
                                                  toAdd.add(suggestions[i]);
                                                }
                                              }
                                              final key =
                                                  _dateKey(_selectedDay);
                                              setState(() {
                                                _wordsByDate[key] ??= {};
                                                final existing = List<
                                                        Map<String, String>>.from(
                                                    _wordsByDate[key]![
                                                            _selectedPerson] ??
                                                        []);
                                                _wordsByDate[key]![
                                                        _selectedPerson] = [
                                                  ...existing,
                                                  ...toAdd
                                                ];
                                                _editorRefreshKey++;
                                              });
                                              Navigator.pop(ctx);
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(SnackBar(
                                                content: Text(
                                                    '$checkedCount개가 추가됐어요. 저장 버튼을 눌러 저장하세요.'),
                                                backgroundColor:
                                                    const Color(0xFF7B1FA2),
                                                behavior:
                                                    SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            10)),
                                              ));
                                            },
                                      icon: const Icon(Icons.add),
                                      label: Text(
                                        checkedCount == 0
                                            ? '선택된 항목이 없어요'
                                            : '$checkedCount개 선택한 날짜에 추가',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF7B1FA2),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        elevation: 0,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  bool _hasWordsOnDay(DateTime day) {
    final list = _wordsByDate[_dateKey(day)]?[_selectedPerson];
    return list != null && list.isNotEmpty;
  }

  List<Map<String, String>> _entriesForSelected() =>
      _wordsByDate[_dateKey(_selectedDay)]?[_selectedPerson] ?? [];

  Map<String, String>? _getDailyExpression() {
    final all = <Map<String, String>>[];
    for (final dateMap in _wordsByDate.values) {
      final entries = dateMap[_selectedPerson];
      if (entries != null) all.addAll(entries);
    }
    if (all.isEmpty) return null;
    final today = DateTime.now();
    final dayOfYear = today.difference(DateTime(today.year, 1, 1)).inDays;
    final seed = today.year * 1000 + dayOfYear;
    return all[seed % all.length];
  }

  List<Map<String, dynamic>> _getReviewItems() {
    final today = DateTime.now();
    final reviews = <Map<String, dynamic>>[];
    for (final gap in [1, 3, 7, 14, 30]) {
      final reviewDate = today.subtract(Duration(days: gap));
      final key = _dateKey(reviewDate);
      final entries = _wordsByDate[key]?[_selectedPerson];
      if (entries != null && entries.isNotEmpty) {
        reviews.add({'date': reviewDate, 'daysAgo': gap, 'entries': entries});
      }
    }
    return reviews;
  }

  @override
  Widget build(BuildContext context) {
    final dailyExpr = _getDailyExpression();
    final reviewItems = _getReviewItems();
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
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p == '준형')
                                const Text('🍔', style: TextStyle(fontSize: 20)),
                              if (p == '준형') const SizedBox(width: 4),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _displayNames[p] ?? p,
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
                            ],
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
                    // 오늘의 표현
                    if (dailyExpr != null) ...[
                      _DailyExpressionCard(
                        word: dailyExpr['word']!,
                        meaning: dailyExpr['meaning']!,
                        tts: _tts,
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 복습 알림
                    if (reviewItems.isNotEmpty) ...[
                      _ReviewCard(
                        items: reviewItems,
                        onTap: (date) => setState(() {
                          _selectedDay = date;
                          _focusedDay = date;
                        }),
                      ),
                      const SizedBox(height: 12),
                    ],

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
                      key: ValueKey('${_dateKey(_selectedDay)}_${_selectedPerson}_$_editorRefreshKey'),
                      day: _selectedDay,
                      person: _selectedPerson,
                      initialEntries: _entriesForSelected(),
                      onChanged: _onEntriesChanged,
                      tts: _tts,
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
                                onWrongAnswers: (wrongs) =>
                                    _saveWrongWords(_selectedPerson, wrongs),
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

                    // 발음 녹음 버튼
                    if (_entriesForSelected()
                        .any((e) => e['word']!.isNotEmpty && e['meaning']!.isNotEmpty)) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RecordScreen(
                                day: _selectedDay,
                                person: _selectedPerson,
                                entries: _entriesForSelected(),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.mic_outlined),
                          label: const Text(
                            '발음 녹음',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6A1B9A),
                            side: const BorderSide(color: Color(0xFF6A1B9A)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],

                    // 오답 노트 버튼
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WrongNoteScreen(
                                person: _selectedPerson),
                          ),
                        ),
                        icon: const Icon(Icons.error_outline),
                        label: const Text(
                          '오답 노트',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFC62828),
                          side: const BorderSide(color: Color(0xFFC62828)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    // 학습 통계 + 즐겨찾기 버튼
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => StatsScreen(
                                    person: _selectedPerson),
                              ),
                            ),
                            icon: const Icon(Icons.bar_chart_outlined),
                            label: const Text('학습 통계',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF1565C0),
                              side: const BorderSide(
                                  color: Color(0xFF1565C0)),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FavoritesScreen(
                                    initialPerson: _selectedPerson),
                              ),
                            ),
                            icon: const Icon(Icons.star_outlined),
                            label: const Text('즐겨찾기',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.amber.shade700,
                              side:
                                  BorderSide(color: Colors.amber.shade700),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // AI 추천 버튼
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _showAiSuggestions(context),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text(
                          'AI 표현 추천',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF7B1FA2),
                          side: const BorderSide(color: Color(0xFF7B1FA2)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    // 전체 단어 목록 버튼
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AllWordsScreen(
                              person: _selectedPerson,
                              wordsByDate: _wordsByDate,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.format_list_numbered),
                        label: const Text(
                          '전체 단어 목록',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00695C),
                          side: const BorderSide(color: Color(0xFF00695C)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

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
  final FlutterTts tts;

  const _DayEditor({
    super.key,
    required this.day,
    required this.person,
    required this.initialEntries,
    required this.onChanged,
    required this.tts,
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
  final _db = FirebaseFirestore.instance;
  Map<String, String> _favWordToDocId = {};

  Future<void> _loadFavorites() async {
    try {
      final snap = await _db
          .collection('favorites')
          .doc(widget.person)
          .collection('words')
          .get();
      final map = <String, String>{};
      for (final doc in snap.docs) {
        final word = doc.data()['word'] as String? ?? '';
        if (word.isNotEmpty) map[word] = doc.id;
      }
      if (mounted) setState(() => _favWordToDocId = map);
    } catch (_) {}
  }

  Future<void> _toggleFavorite(int i) async {
    final word = _wordCtrls[i].text.trim();
    final meaning = _meaningCtrls[i].text.trim();
    if (word.isEmpty) return;
    final dayKey =
        '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';
    if (_favWordToDocId.containsKey(word)) {
      final docId = _favWordToDocId[word]!;
      await _db
          .collection('favorites')
          .doc(widget.person)
          .collection('words')
          .doc(docId)
          .delete();
      if (mounted) setState(() => _favWordToDocId.remove(word));
    } else {
      final ref = await _db
          .collection('favorites')
          .doc(widget.person)
          .collection('words')
          .add({
        'word': word,
        'meaning': meaning,
        'dateKey': dayKey,
        'addedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _favWordToDocId[word] = ref.id);
    }
  }

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
    _loadFavorites();
  }

  @override
  void dispose() {
    for (final c in _wordCtrls) c.dispose();
    for (final c in _meaningCtrls) c.dispose();
    for (final n in _wordNodes) n.dispose();
    for (final n in _meaningNodes) n.dispose();
    super.dispose();
  }

  // ── 일괄 추가 ─────────────────────────────────────────

  static List<Map<String, String>> _parseText(String text) =>
      _parseWordEntries(text);

  List<Map<String, String>> _deduplicate(List<Map<String, String>> incoming) {
    final existing = _wordCtrls
        .map((c) => c.text.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    return incoming
        .where((e) => !existing.contains(e['word']!.toLowerCase()))
        .toList();
  }

  Future<List<Map<String, String>>> _fetchMoreFromGemini(
      List<Map<String, String>> sample) async {
    final examples = sample
        .take(10)
        .map((e) => '${e['word']} (${e['meaning']})')
        .join('\n');
    final prompt = '''다음은 영어 표현 학습 목록입니다:
$examples

위와 같은 주제/상황에서 쓰는 영어 표현 20개를 추가로 만들어주세요.
- 위 목록과 겹치지 않아야 해요
- 반드시 아래 형식으로만 출력하세요 (번호, 설명 없이):
English sentence. (한국어 뜻)''';

    final res = await http.post(
      Uri.parse(_geminiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1024},
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
      return _deduplicate(_parseText(text));
    }

    // 에러 응답에서 메시지 추출
    String errMsg = 'HTTP ${res.statusCode}';
    try {
      final errData = jsonDecode(res.body) as Map<String, dynamic>;
      errMsg = errData['error']?['message'] as String? ?? errMsg;
    } catch (_) {}
    throw Exception(errMsg);
  }

  void _addRows(List<Map<String, String>> entries) {
    // 마지막 빈 행 앞에 삽입
    final insertAt = (_wordCtrls.isNotEmpty &&
            _wordCtrls.last.text.isEmpty &&
            _meaningCtrls.last.text.isEmpty)
        ? _wordCtrls.length - 1
        : _wordCtrls.length;

    for (final e in entries) {
      _wordCtrls.insert(insertAt, TextEditingController(text: e['word']));
      _meaningCtrls.insert(insertAt, TextEditingController(text: e['meaning']));
      _wordNodes.insert(insertAt, FocusNode());
      _meaningNodes.insert(insertAt, FocusNode());
    }
    _onChanged(0);
  }

  void _showBulkImport() {
    final textCtrl = TextEditingController();
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('📋 일괄 추가',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('1. English sentence (한국어 뜻) 형식으로 붙여넣으세요',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  maxLines: 8,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '1. A table for two, please. (두 명 자리가 있을까요?)\n2. ...',
                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF1565C0)),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 16),
                if (loading)
                  const Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(color: Color(0xFF1565C0)),
                        SizedBox(height: 8),
                        Text('AI로 관련 표현 생성 중...', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final parsed = _parseText(textCtrl.text);
                        if (parsed.isEmpty) return;
                        final deduped = _deduplicate(parsed);

                        setModal(() => loading = true);
                        List<Map<String, String>> more = [];
                        String? aiError;
                        try {
                          more = await _fetchMoreFromGemini(parsed);
                        } catch (e) {
                          aiError = e.toString().replaceFirst('Exception: ', '');
                        } finally {
                          setModal(() => loading = false);
                        }

                        setState(() => _addRows([...deduped, ...more]));
                        if (ctx.mounted) Navigator.pop(ctx);

                        final added = deduped.length + more.length;
                        final skipped = parsed.length - deduped.length;
                        if (context.mounted) {
                          if (aiError != null) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('파싱 ${deduped.length}개 추가됨 / AI 오류: $aiError'),
                              backgroundColor: Colors.orange.shade700,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 6),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                '$added개 추가됨'
                                '${skipped > 0 ? ' ($skipped개 중복 제외)' : ''}'
                                '${more.isNotEmpty ? ', AI로 ${more.length}개 추가' : ''}',
                              ),
                              backgroundColor: const Color(0xFF1565C0),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ));
                          }
                        }
                      },
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('파싱 + AI 자동 추가',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _deleteRow(int index) {
    if (_wordCtrls.length <= 1) {
      _wordCtrls[0].clear();
      _meaningCtrls[0].clear();
    } else {
      _wordCtrls[index].dispose();
      _meaningCtrls[index].dispose();
      _wordNodes[index].dispose();
      _meaningNodes[index].dispose();
      _wordCtrls.removeAt(index);
      _meaningCtrls.removeAt(index);
      _wordNodes.removeAt(index);
      _meaningNodes.removeAt(index);
    }
    _onChanged(0);
  }

  Future<void> _confirmDeleteAll() async {
    final hasContent = _wordCtrls.any((c) => c.text.isNotEmpty);
    if (!hasContent) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('전체 삭제', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '${widget.day.month}월 ${widget.day.day}일 · ${widget.person}\n\n모든 표현을 삭제할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      for (final c in _wordCtrls) c.dispose();
      for (final c in _meaningCtrls) c.dispose();
      for (final n in _wordNodes) n.dispose();
      for (final n in _meaningNodes) n.dispose();
      _wordCtrls = [TextEditingController()];
      _meaningCtrls = [TextEditingController()];
      _wordNodes = [FocusNode()];
      _meaningNodes = [FocusNode()];
    });
    widget.onChanged([]);
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
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Text(
                  '${widget.day.month}월 ${widget.day.day}일 · ${widget.person}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: _blue,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showBulkImport,
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('일괄 추가', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                    foregroundColor: _blue,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                IconButton(
                  onPressed: _confirmDeleteAll,
                  icon: Icon(Icons.delete_sweep_outlined,
                      size: 20, color: Colors.red.shade300),
                  tooltip: '전체 삭제',
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // 컬럼 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(58, 0, 36, 4),
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
              final wordText = _wordCtrls[i].text.trim();
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
                  const SizedBox(width: 6),
                  // TTS 버튼
                  SizedBox(
                    width: 28,
                    child: wordText.isNotEmpty
                        ? GestureDetector(
                            onTap: () => widget.tts.speak(wordText),
                            child: Icon(Icons.volume_up_outlined,
                                size: 18,
                                color: Colors.blue.shade300),
                          )
                        : const SizedBox(),
                  ),
                  const SizedBox(width: 4),
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
                  // 개별 삭제 + 즐겨찾기 버튼
                  if (!isEmpty) ...[
                    GestureDetector(
                      onTap: () => setState(() => _deleteRow(i)),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(Icons.close,
                            size: 16, color: Colors.grey.shade400),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _toggleFavorite(i),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          _favWordToDocId.containsKey(wordText)
                              ? Icons.star
                              : Icons.star_border,
                          size: 16,
                          color: _favWordToDocId.containsKey(wordText)
                              ? Colors.amber
                              : Colors.grey.shade300,
                        ),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 20),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DailyExpressionCard extends StatelessWidget {
  final String word;
  final String meaning;
  final FlutterTts tts;
  const _DailyExpressionCard(
      {required this.word, required this.meaning, required this.tts});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1565C0), Color(0xFF1E88E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined,
                  color: Colors.white70, size: 15),
              const SizedBox(width: 6),
              const Text(
                '오늘의 표현',
                style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => tts.speak(word),
                child: const Icon(Icons.volume_up_outlined,
                    color: Colors.white70, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(word,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(meaning,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 14)),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(DateTime) onTap;
  const _ReviewCard({required this.items, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_outlined,
                  color: Colors.orange.shade700, size: 17),
              const SizedBox(width: 6),
              Text(
                '복습할 시간이에요!',
                style: TextStyle(
                    color: Colors.orange.shade800,
                    fontSize: 13,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) {
            final date = item['date'] as DateTime;
            final daysAgo = item['daysAgo'] as int;
            final entries = item['entries'] as List;
            return GestureDetector(
              onTap: () => onTap(date),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        '$daysAgo일 전',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade700,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${date.month}/${date.day} 학습 ${entries.length}개',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_ios,
                        size: 12, color: Colors.grey.shade400),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
