import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AllWordsScreen extends StatefulWidget {
  final String person;
  final Map<String, Map<String, List<Map<String, String>>>> wordsByDate;

  const AllWordsScreen({
    super.key,
    required this.person,
    required this.wordsByDate,
  });

  @override
  State<AllWordsScreen> createState() => _AllWordsScreenState();
}

class _AllWordsScreenState extends State<AllWordsScreen> {
  static const _blue = Color(0xFF1565C0);
  final _tts = FlutterTts();
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  late List<_WordItem> _allWords;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _buildList();
  }

  @override
  void dispose() {
    _tts.stop();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _buildList() {
    final sortedDates = widget.wordsByDate.keys.toList()..sort();
    final list = <_WordItem>[];
    int num = 1;
    for (final dateKey in sortedDates) {
      final entries = widget.wordsByDate[dateKey]?[widget.person];
      if (entries == null) continue;
      for (final e in entries) {
        final word = e['word'] ?? '';
        final meaning = e['meaning'] ?? '';
        if (word.isEmpty && meaning.isEmpty) continue;
        list.add(_WordItem(number: num++, word: word, meaning: meaning, dateKey: dateKey));
      }
    }
    _allWords = list;
  }

  List<_WordItem> get _filtered {
    if (_searchQuery.isEmpty) return _allWords;
    final q = _searchQuery.toLowerCase();
    return _allWords
        .where((e) =>
            e.word.toLowerCase().contains(q) ||
            e.meaning.toLowerCase().contains(q))
        .toList();
  }

  String _formatDate(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return key;
    return '${parts[0]}년 ${int.parse(parts[1])}월 ${int.parse(parts[2])}일';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final isSearching = _searchQuery.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text('전체 단어 · ${widget.person}'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 검색창
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: '단어 또는 뜻 검색',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: _blue, size: 20),
                suffixIcon: isSearching
                    ? IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey.shade400, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // 총 개수 표시
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Text(
                  isSearching
                      ? '${filtered.length} / ${_allWords.length}개'
                      : '총 ${_allWords.length}개',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // 단어 목록
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      isSearching ? '검색 결과가 없어요' : '단어가 없어요',
                      style: TextStyle(fontSize: 15, color: Colors.grey.shade400),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final item = filtered[i];

                      // 검색 중이 아닐 때만 날짜 구분선 표시
                      final showDateHeader = !isSearching &&
                          (i == 0 || filtered[i - 1].dateKey != item.dateKey);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showDateHeader)
                            Padding(
                              padding: EdgeInsets.fromLTRB(4, i == 0 ? 4 : 14, 0, 6),
                              child: Row(
                                children: [
                                  Container(
                                    width: 3,
                                    height: 13,
                                    decoration: BoxDecoration(
                                      color: _blue,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _formatDate(item.dateKey),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: _blue,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          Container(
                            margin: const EdgeInsets.only(bottom: 5),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // 번호
                                SizedBox(
                                  width: 38,
                                  child: Text(
                                    '${item.number}.',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: _blue,
                                    ),
                                  ),
                                ),
                                // 단어 + 뜻
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.word,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      if (item.meaning.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          item.meaning,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // TTS 버튼
                                if (item.word.isNotEmpty)
                                  GestureDetector(
                                    onTap: () => _tts.speak(item.word),
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: Icon(
                                        Icons.volume_up_outlined,
                                        size: 20,
                                        color: Colors.blue.shade300,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _WordItem {
  final int number;
  final String word;
  final String meaning;
  final String dateKey;

  const _WordItem({
    required this.number,
    required this.word,
    required this.meaning,
    required this.dateKey,
  });
}
