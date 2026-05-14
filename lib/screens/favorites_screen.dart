import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FavoritesScreen extends StatefulWidget {
  final String initialPerson;
  const FavoritesScreen({super.key, required this.initialPerson});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _db = FirebaseFirestore.instance;
  late String _person;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  static const _blue = Color(0xFF1565C0);
  static const _persons = ['영욱', '준형'];

  @override
  void initState() {
    super.initState();
    _person = widget.initialPerson;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await _db
          .collection('favorites')
          .doc(_person)
          .collection('words')
          .get();
      if (mounted) {
        final items = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        items.sort((a, b) {
          final ak = a['dateKey'] as String? ?? '';
          final bk = b['dateKey'] as String? ?? '';
          return bk.compareTo(ak);
        });
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(String id) async {
    try {
      await _db
          .collection('favorites')
          .doc(_person)
          .collection('words')
          .doc(id)
          .delete();
      if (mounted) setState(() => _items.removeWhere((e) => e['id'] == id));
    } catch (_) {}
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
              padding: const EdgeInsets.fromLTRB(8, 12, 16, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_ios,
                            color: Colors.white),
                      ),
                      const Text(
                        '즐겨찾기',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: _persons.map((p) {
                      final selected = _person == p;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                              left: 8, right: p == '영욱' ? 4 : 8),
                          child: GestureDetector(
                            onTap: () {
                              if (_person != p) {
                                setState(() => _person = p);
                                _load();
                              }
                            },
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                p,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: selected ? _blue : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _blue))
                  : _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star_border,
                                  size: 64, color: Colors.grey.shade300),
                              const SizedBox(height: 12),
                              Text(
                                '즐겨찾기한 표현이 없어요\n단어 목록에서 ★를 눌러보세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    height: 1.6,
                                    fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            return Dismissible(
                              key: Key(item['id'] as String),
                              direction: DismissDirection.endToStart,
                              onDismissed: (_) => _remove(item['id'] as String),
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding:
                                    const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade400,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.star_outlined,
                                    color: Colors.white),
                              ),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.05),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2))
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 18, color: Colors.amber),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['word'] as String? ?? '',
                                            style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item['meaning'] as String? ?? '',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600),
                                          ),
                                          if ((item['dateKey'] as String?)
                                                  ?.isNotEmpty ==
                                              true)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 4),
                                              child: Text(
                                                item['dateKey'] as String,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors
                                                        .grey.shade400),
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
          ],
        ),
      ),
    );
  }
}
