import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_tts/flutter_tts.dart';

class WrongNoteScreen extends StatefulWidget {
  final String person;

  const WrongNoteScreen({super.key, required this.person});

  @override
  State<WrongNoteScreen> createState() => _WrongNoteScreenState();
}

class _WrongNoteScreenState extends State<WrongNoteScreen> {
  static const _blue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF1E88E5);
  static const _red = Color(0xFFC62828);
  static const _green = Color(0xFF2E7D32);

  final _db = FirebaseFirestore.instance;
  final _tts = FlutterTts();

  List<Map<String, String>> _wrongWords = [];
  bool _loading = true;

  // 테스트 모드
  bool _testMode = false;
  bool _isRandom = false;
  late List<Map<String, String>> _quizEntries;
  int _currentIndex = 0;
  final TextEditingController _answerCtrl = TextEditingController();
  final FocusNode _answerFocus = FocusNode();
  int _hintLevel = 0;
  bool? _isCorrect;
  int _score = 0;
  final List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _loadWrongWords();
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    _answerFocus.dispose();
    _tts.stop();
    super.dispose();
  }

  Future<void> _loadWrongWords() async {
    final snapshot = await _db
        .collection('wrong_notes')
        .doc(widget.person)
        .collection('words')
        .get();

    setState(() {
      _wrongWords = snapshot.docs.map((doc) {
        final d = doc.data();
        return {
          'id': doc.id,
          'word': d['word']?.toString() ?? '',
          'meaning': d['meaning']?.toString() ?? '',
        };
      }).toList();
      _loading = false;
    });
  }

  Future<void> _deleteWord(String id) async {
    await _db
        .collection('wrong_notes')
        .doc(widget.person)
        .collection('words')
        .doc(id)
        .delete();
    setState(() => _wrongWords.removeWhere((w) => w['id'] == id));
  }

  void _startTest() {
    final list = List<Map<String, String>>.from(_wrongWords);
    if (_isRandom) list.shuffle(Random());
    setState(() {
      _testMode = true;
      _quizEntries = list;
      _currentIndex = 0;
      _isCorrect = null;
      _hintLevel = 0;
      _score = 0;
      _results.clear();
      _answerCtrl.clear();
    });
  }

  void _exitTest() {
    setState(() {
      _testMode = false;
      _isCorrect = null;
    });
  }

  String get _question => _quizEntries[_currentIndex]['meaning']!;
  String get _correctAnswer => _quizEntries[_currentIndex]['word']!;

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

  bool get _finished => _results.length >= _quizEntries.length;

  @override
  Widget build(BuildContext context) {
    if (_testMode && !_finished) return _buildQuiz(context);
    if (_testMode && _finished) return _buildResult(context);
    return _buildList(context);
  }

  // ── 오답 목록 ────────────────────────────────────────────────────────────────

  Widget _buildList(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text('오답 노트 · ${widget.person}'),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _wrongWords.isEmpty
              ? const Center(
                  child: Text(
                    '틀린 단어가 없어요!',
                    style: TextStyle(fontSize: 16, color: Colors.black45),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _wrongWords.length,
                        itemBuilder: (_, i) {
                          final w = _wrongWords[i];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
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
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              w['word']!,
                                              style: const TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () =>
                                                _tts.speak(w['word']!),
                                            icon: const Icon(
                                                Icons.volume_up_outlined,
                                                size: 20),
                                            color: _lightBlue,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        w['meaning']!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _confirmDelete(context, w),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  color: Colors.red.shade300,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      child: Column(
                        children: [
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
                                  onTap: () =>
                                      setState(() => _isRandom = false),
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
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _wrongWords.isEmpty ? null : _startTest,
                              icon: const Icon(Icons.quiz_outlined),
                              label: const Text(
                                '오답 테스트 시작',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  void _confirmDelete(BuildContext context, Map<String, String> w) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: Text('"${w['word']}" 를 오답 노트에서 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteWord(w['id']!);
            },
            child:
                const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ── 퀴즈 화면 ────────────────────────────────────────────────────────────────

  Widget _buildQuiz(BuildContext context) {
    final total = _quizEntries.length;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        title: Text('오답 테스트  ${_currentIndex + 1} / $total'),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _exitTest,
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${_score}점',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: _currentIndex / total,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
            minHeight: 4,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
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
                        Text(
                          '뜻',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400,
                              letterSpacing: 1),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _question,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
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
                            color: Color(0xFFF57F17)),
                      ),
                    ),
                  if (_hintLevel > 0) const SizedBox(height: 16),
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
                            color: _isCorrect! ? _green : _red),
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
                                color: _isCorrect! ? _green : _red),
                          ),
                        ],
                      ),
                    ),
                  if (_isCorrect != null) const SizedBox(height: 16),
                  if (_isCorrect == null) ...[
                    TextField(
                      controller: _answerCtrl,
                      focusNode: _answerFocus,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: '영어 단어 입력',
                        hintStyle:
                            TextStyle(color: Colors.grey.shade400),
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
                              const BorderSide(color: _red, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _hintLevel < 2 ? () => setState(() => _hintLevel++) : null,
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
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: const Text('제출',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_isCorrect != null)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
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

  // ── 결과 화면 ────────────────────────────────────────────────────────────────

  Widget _buildResult(BuildContext context) {
    final total = _quizEntries.length;
    final pct = (_score / total * 100).round();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _red,
        foregroundColor: Colors.white,
        title: const Text('오답 테스트 결과'),
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
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
                      color:
                          pct >= 80 ? _green : pct >= 50 ? _blue : _red,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$total개 중 $_score개 정답',
                      style: const TextStyle(
                          fontSize: 16, color: Colors.black54)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_results.any((r) => !(r['isCorrect'] as bool))) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('틀린 문제',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600)),
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
                          Text(r['question'] as String,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(Icons.close,
                                size: 14, color: Colors.red.shade400),
                            const SizedBox(width: 4),
                            Text(r['user'] as String,
                                style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontSize: 13)),
                          ]),
                          Row(children: [
                            Icon(Icons.check,
                                size: 14, color: Colors.green.shade600),
                            const SizedBox(width: 4),
                            Text(r['correct'] as String,
                                style: TextStyle(
                                    color: Colors.green.shade600,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold)),
                          ]),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _exitTest,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('목록으로',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _startTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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

  static const _red = Color(0xFFC62828);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? _red : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color:
                      selected ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color:
                      selected ? Colors.white : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
