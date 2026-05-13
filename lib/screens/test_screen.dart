import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum TestMode { korToEng, engToKor }

class TestScreen extends StatefulWidget {
  final DateTime day;
  final String person;
  final List<Map<String, String>> entries;
  final Future<void> Function(List<Map<String, String>>)? onWrongAnswers;

  const TestScreen({
    super.key,
    required this.day,
    required this.person,
    required this.entries,
    this.onWrongAnswers,
  });

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  TestMode? _mode;
  bool _isRandom = false;
  late List<Map<String, String>> _quizEntries;
  int _currentIndex = 0;
  final TextEditingController _answerCtrl = TextEditingController();
  final FocusNode _answerFocus = FocusNode();
  int _hintLevel = 0;
  bool? _isCorrect;
  int _score = 0;
  final List<Map<String, dynamic>> _results = [];
  final _tts = FlutterTts();

  static const _blue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF1E88E5);
  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);

  List<Map<String, String>> get _validEntries => widget.entries
      .where((e) => e['word']!.isNotEmpty && e['meaning']!.isNotEmpty)
      .toList();

  bool get _finished => _results.length >= _quizEntries.length;

  void _startTest(TestMode mode) {
    final list = List<Map<String, String>>.from(_validEntries);
    if (_isRandom) list.shuffle(Random());
    setState(() {
      _mode = mode;
      _quizEntries = list;
    });
  }

  String get _question {
    final e = _quizEntries[_currentIndex];
    return _mode == TestMode.korToEng ? e['meaning']! : e['word']!;
  }

  String get _correctAnswer {
    final e = _quizEntries[_currentIndex];
    return _mode == TestMode.korToEng ? e['word']! : e['meaning']!;
  }

  String _buildHint() {
    final ans = _correctAnswer;
    final buffer = StringBuffer();
    int revealed = 0;
    for (final ch in ans.runes) {
      final c = String.fromCharCode(ch);
      if (c == ' ') {
        buffer.write('  ');
      } else if (revealed < _hintLevel) {
        buffer.write(c);
        revealed++;
      } else {
        buffer.write('_');
      }
    }
    return buffer.toString();
  }

  void _submit() {
    final input = _answerCtrl.text.trim();
    if (input.isEmpty) return;
    final correct = input.toLowerCase() == _correctAnswer.toLowerCase();
    setState(() {
      _isCorrect = correct;
      if (correct) _score++;
      _results.add({
        'question': _question,
        'correct': _correctAnswer,
        'user': input,
        'isCorrect': correct,
      });
    });
  }

  void _next() {
    setState(() {
      _currentIndex++;
      _isCorrect = null;
      _hintLevel = 0;
      _answerCtrl.clear();
    });
    _answerFocus.requestFocus();
  }

  void _showHint() {
    if (_hintLevel < 2) setState(() => _hintLevel++);
  }

  void _retry() {
    final list = List<Map<String, String>>.from(_validEntries);
    if (_isRandom) list.shuffle(Random());
    setState(() {
      _quizEntries = list;
      _currentIndex = 0;
      _isCorrect = null;
      _hintLevel = 0;
      _score = 0;
      _results.clear();
      _answerCtrl.clear();
      _mode = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    _answerFocus.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == null) return _buildModeSelect(context);
    if (_finished) return _buildResult(context);
    return _buildQuiz(context);
  }

  // ── 모드 선택 ──────────────────────────────────────────────────────────────

  Widget _buildModeSelect(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('테스트 모드 선택'),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${widget.day.month}월 ${widget.day.day}일 · ${widget.person}',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_validEntries.length}개',
              style: const TextStyle(fontSize: 14, color: Colors.black38),
            ),
            const SizedBox(height: 32),

            // 순서 토글
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _OrderToggle(
                    label: '순서대로',
                    icon: Icons.format_list_numbered,
                    selected: !_isRandom,
                    onTap: () => setState(() => _isRandom = false),
                  ),
                  _OrderToggle(
                    label: '랜덤',
                    icon: Icons.shuffle,
                    selected: _isRandom,
                    onTap: () => setState(() => _isRandom = true),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _ModeCard(
              icon: Icons.translate,
              title: '한 → 영',
              subtitle: '한국어 뜻을 보고 영어 단어 맞추기',
              onTap: () => _startTest(TestMode.korToEng),
            ),
            const SizedBox(height: 16),
            _ModeCard(
              icon: Icons.spellcheck,
              title: '영 → 한',
              subtitle: '영어 단어를 보고 한국어 뜻 맞추기',
              onTap: () => _startTest(TestMode.engToKor),
            ),
          ],
        ),
      ),
    );
  }

  // ── 퀴즈 화면 ──────────────────────────────────────────────────────────────

  Widget _buildQuiz(BuildContext context) {
    final total = _quizEntries.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text('${_currentIndex + 1} / $total'),
        elevation: 0,
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_score}점',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _currentIndex / total,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(_lightBlue),
            minHeight: 4,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 문제 카드
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 36, horizontal: 24),
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
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _mode == TestMode.korToEng ? '뜻' : '단어',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade400,
                                letterSpacing: 1,
                              ),
                            ),
                            if (_mode == TestMode.engToKor) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _tts.speak(_question),
                                child: Icon(Icons.volume_up_outlined,
                                    size: 18,
                                    color: Colors.blue.shade300),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _question,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 힌트 표시
                  if (_hintLevel > 0)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF9C4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF9A825)),
                      ),
                      child: Text(
                        _buildHint(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                          color: Color(0xFFF57F17),
                        ),
                      ),
                    ),

                  if (_hintLevel > 0) const SizedBox(height: 16),

                  // 정답/오답 결과
                  if (_isCorrect != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      decoration: BoxDecoration(
                        color: _isCorrect!
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isCorrect! ? _green : _red,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isCorrect! ? Icons.check_circle : Icons.cancel,
                            color: _isCorrect! ? _green : _red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isCorrect! ? '정답!' : '정답: $_correctAnswer',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _isCorrect! ? _green : _red,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isCorrect != null) const SizedBox(height: 16),

                  // 입력 + 버튼 (미제출)
                  if (_isCorrect == null) ...[
                    TextField(
                      controller: _answerCtrl,
                      focusNode: _answerFocus,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: _mode == TestMode.korToEng
                            ? '영어 단어 입력'
                            : '한국어 뜻 입력',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: _blue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _hintLevel < 2 ? _showHint : null,
                          icon: const Icon(Icons.lightbulb_outline, size: 18),
                          label: Text('힌트 (${2 - _hintLevel}회)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _hintLevel < 2
                                ? const Color(0xFFF57F17)
                                : Colors.grey,
                            side: BorderSide(
                                color: _hintLevel < 2
                                    ? const Color(0xFFF57F17)
                                    : Colors.grey),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _blue,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              '제출',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // 다음 버튼 (제출 후)
                  if (_isCorrect != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          _currentIndex + 1 >= total ? '결과 보기' : '다음 →',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 결과 화면 ──────────────────────────────────────────────────────────────

  Widget _buildResult(BuildContext context) {
    final total = _quizEntries.length;
    final pct = (_score / total * 100).round();

    // 틀린 단어 오답 노트 자동 저장 (한 번만)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.onWrongAnswers != null) {
        final wrongs = _results
            .where((r) => !(r['isCorrect'] as bool))
            .map((r) {
              final e = _quizEntries.firstWhere(
                  (q) => (_mode == TestMode.korToEng
                      ? q['meaning']
                      : q['word']) ==
                      r['question']);
              return {'word': e['word']!, 'meaning': e['meaning']!};
            })
            .toList();
        if (wrongs.isNotEmpty) widget.onWrongAnswers!(wrongs);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: const Text('테스트 결과'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // 점수 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
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
                children: [
                  Text(
                    '$pct점',
                    style: TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.bold,
                      color: pct >= 80 ? _green : pct >= 50 ? _blue : _red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total개 중 $_score개 정답',
                    style: const TextStyle(
                        fontSize: 16, color: Colors.black54),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 틀린 문제 리뷰
            if (_results.any((r) => !(r['isCorrect'] as bool))) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '틀린 문제',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ..._results.where((r) => !(r['isCorrect'] as bool)).map(
                    (r) => Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['question'] as String,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.close,
                                  size: 14, color: Colors.red.shade400),
                              const SizedBox(width: 4),
                              Text(
                                r['user'] as String,
                                style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Icon(Icons.check,
                                  size: 14,
                                  color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text(
                                r['correct'] as String,
                                style: TextStyle(
                                  color: Colors.green.shade600,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
            ],

            // 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: const BorderSide(color: _blue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('홈으로',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('다시 풀기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 순서 토글 버튼 ────────────────────────────────────────────────────────────

class _OrderToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _OrderToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _blue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.white : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 모드 선택 카드 ────────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  static const _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: _blue, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios,
                color: Colors.grey.shade400, size: 16),
          ],
        ),
      ),
    );
  }
}
