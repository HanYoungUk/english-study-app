import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StatsScreen extends StatefulWidget {
  final String person;
  const StatsScreen({super.key, required this.person});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  int _totalWords = 0;
  int _totalDays = 0;
  List<_DayActivity> _recentActivity = [];
  List<Map<String, dynamic>> _testHistory = [];

  static const _blue = Color(0xFF1565C0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    final today = DateTime.now();
    final wordsSnap = await _db.collection('words').get();

    int total = 0;
    int days = 0;
    final last7 = List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return _DayActivity(date: d, count: 0);
    });

    for (final doc in wordsSnap.docs) {
      final entries = doc.data()[widget.person];
      if (entries is List && entries.isNotEmpty) {
        days++;
        total += entries.length;
        for (final da in last7) {
          if (_dateKey(da.date) == doc.id) {
            da.count = entries.length;
            break;
          }
        }
      }
    }

    List<Map<String, dynamic>> tests = [];
    try {
      final testSnap = await _db
          .collection('test_results')
          .where('person', isEqualTo: widget.person)
          .get();
      tests = testSnap.docs.map((d) => d.data()).toList();
      tests.sort((a, b) {
        final ak = a['dateKey'] as String? ?? '';
        final bk = b['dateKey'] as String? ?? '';
        return bk.compareTo(ak);
      });
      if (tests.length > 15) tests = tests.sublist(0, 15);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _totalWords = total;
        _totalDays = days;
        _recentActivity = last7;
        _testHistory = tests;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_blue, Color(0xFF1E88E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                  ),
                  Text(
                    '${widget.person}의 학습 통계',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _blue))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  label: '총 학습 단어',
                                  value: '$_totalWords개',
                                  icon: Icons.book_outlined,
                                  color: _blue,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: '학습한 날',
                                  value: '$_totalDays일',
                                  icon: Icons.calendar_today_outlined,
                                  color: Colors.teal,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  label: '일평균',
                                  value: _totalDays > 0
                                      ? '${(_totalWords / _totalDays).toStringAsFixed(1)}개'
                                      : '-',
                                  icon: Icons.trending_up,
                                  color: Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _section('최근 7일 활동', _buildActivityChart()),
                          if (_testHistory.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _section('테스트 기록', _buildTestHistory()),
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

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _blue)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildActivityChart() {
    if (_recentActivity.isEmpty) {
      return Text('데이터 없음',
          style: TextStyle(color: Colors.grey.shade500));
    }
    final maxCount = _recentActivity
        .map((e) => e.count)
        .fold(0, (a, b) => a > b ? a : b);
    const days = ['일', '월', '화', '수', '목', '금', '토'];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _recentActivity.map((da) {
        final barH =
            maxCount > 0 ? (da.count / maxCount * 80).clamp(4.0, 80.0) : 4.0;
        final isToday = _dateKey(da.date) == _dateKey(DateTime.now());
        final hasData = da.count > 0;
        return Expanded(
          child: Column(
            children: [
              Text(
                hasData ? '${da.count}' : '',
                style: TextStyle(
                    fontSize: 10,
                    color: isToday ? _blue : Colors.grey.shade500),
              ),
              const SizedBox(height: 4),
              Container(
                height: barH,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: hasData
                      ? (isToday ? _blue : const Color(0xFF90CAF9))
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                days[da.date.weekday % 7],
                style: TextStyle(
                  fontSize: 11,
                  color: isToday ? _blue : Colors.grey.shade600,
                  fontWeight:
                      isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTestHistory() {
    return Column(
      children: _testHistory.map((t) {
        final total = t['total'] as int? ?? 0;
        final correct = t['correct'] as int? ?? 0;
        final pct =
            total > 0 ? (correct / total * 100).round() : 0;
        final dateKey = t['dateKey'] as String? ?? '';
        final quizType = t['quizType'] as String? ?? 'subjective';
        final isMC = quizType == 'multipleChoice';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isMC
                      ? Colors.orange.shade100
                      : _blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMC ? '객관식' : '주관식',
                  style: TextStyle(
                    fontSize: 11,
                    color: isMC ? Colors.orange.shade700 : _blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(dateKey,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.black54)),
              ),
              Text('$correct / $total',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      pct >= 80 ? Colors.green : Colors.red.shade400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DayActivity {
  final DateTime date;
  int count;
  _DayActivity({required this.date, required this.count});
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}
