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
  late Set<String> _activeDates;
  late List<String> _allDates;

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
    _allDates = sortedDates
        .where((d) => widget.wordsByDate[d]?[widget.person]?.isNotEmpty == true)
        .toList();
    _activeDates = Set.from(_allDates);

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
    var list = _allWords.where((e) => _activeDates.contains(e.dateKey)).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list
          .where((e) =>
              e.word.toLowerCase().contains(q) ||
              e.meaning.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  bool get _isFiltered => _activeDates.length < _allDates.length;

  void _showDateFilter() {
    final tempSelected = Set<String>.from(_activeDates);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (_, scrollCtrl) => StatefulBuilder(
          builder: (ctx, setModal) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: _blue, size: 18),
                      const SizedBox(width: 8),
                      const Text('날짜 필터',
                          style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setModal(() {
                          if (tempSelected.length == _allDates.length) {
                            tempSelected.clear();
                          } else {
                            tempSelected.addAll(_allDates);
                          }
                        }),
                        child: Text(
                          tempSelected.length == _allDates.length
                              ? '전체 해제'
                              : '전체 선택',
                          style: const TextStyle(color: _blue, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _allDates.length,
                    itemBuilder: (_, i) {
                      final date = _allDates[i];
                      final isOn = tempSelected.contains(date);
                      final count = widget.wordsByDate[date]?[widget.person]
                              ?.where((e) =>
                                  (e['word'] ?? '').isNotEmpty ||
                                  (e['meaning'] ?? '').isNotEmpty)
                              .length ??
                          0;
                      return InkWell(
                        onTap: () => setModal(() {
                          if (isOn) {
                            tempSelected.remove(date);
                          } else {
                            tempSelected.add(date);
                          }
                        }),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isOn
                                ? const Color(0xFFE3F2FD)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isOn
                                  ? _blue.withValues(alpha: 0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isOn
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: isOn ? _blue : Colors.grey.shade300,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _formatDate(date),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isOn
                                        ? Colors.black87
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                              Text(
                                '$count개',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isOn
                                      ? _blue
                                      : Colors.grey.shade400,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: tempSelected.isEmpty
                            ? null
                            : () {
                                setState(() => _activeDates =
                                    Set.from(tempSelected));
                                Navigator.pop(ctx);
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          tempSelected.isEmpty
                              ? '날짜를 선택해주세요'
                              : '${tempSelected.length}개 날짜 적용',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
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
        actions: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showDateFilter,
                tooltip: '날짜 필터',
              ),
              if (_isFiltered)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ],
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
                      : _isFiltered
                          ? '${filtered.length}개 (${_activeDates.length}개 날짜 필터 중)'
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
