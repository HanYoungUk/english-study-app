import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

class RecordScreen extends StatefulWidget {
  final DateTime day;
  final String person;
  final List<Map<String, String>> entries;

  const RecordScreen({
    super.key,
    required this.day,
    required this.person,
    required this.entries,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  static const _blue = Color(0xFF1565C0);
  static const _lightBlue = Color(0xFF1E88E5);
  static const _red = Color(0xFFC62828);

  late List<Map<String, String>> _entries;
  int _currentIndex = 0;

  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _tts = FlutterTts();

  bool _isRecording = false;
  bool _isPlayingTts = false;
  bool _isPlayingRecord = false;

  // 각 단어별 녹음 파일 경로 저장
  Map<int, String> _recordPaths = {};

  @override
  void initState() {
    super.initState();
    _entries = widget.entries
        .where((e) => e['word']!.isNotEmpty && e['meaning']!.isNotEmpty)
        .toList();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    _tts.setCompletionHandler(() => setState(() => _isPlayingTts = false));

    _player.onPlayerComplete.listen((_) {
      setState(() => _isPlayingRecord = false);
    });
  }

  @override
  void dispose() {
    _recorder.dispose();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  Map<String, String> get _current => _entries[_currentIndex];

  Future<String> _recordFilePath(int index) async {
    final dir = await getApplicationDocumentsDirectory();
    final person = widget.person;
    final dateKey =
        '${widget.day.year}-${widget.day.month.toString().padLeft(2, '0')}-${widget.day.day.toString().padLeft(2, '0')}';
    return '${dir.path}/recordings/${person}_${dateKey}_$index.m4a';
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final path = await _recordFilePath(_currentIndex);
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }

    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (path != null) {
      setState(() {
        _recordPaths[_currentIndex] = path;
        _isRecording = false;
      });
    }
  }

  Future<void> _playRecording() async {
    final path = _recordPaths[_currentIndex];
    if (path == null) return;
    await _player.stop();
    setState(() => _isPlayingRecord = true);
    await _player.play(DeviceFileSource(path));
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    setState(() => _isPlayingRecord = false);
  }

  Future<void> _playTts() async {
    setState(() => _isPlayingTts = true);
    await _tts.speak(_current['word']!);
  }

  Future<void> _stopTts() async {
    await _tts.stop();
    setState(() => _isPlayingTts = false);
  }

  bool get _hasRecording => _recordPaths.containsKey(_currentIndex);

  Future<void> _goTo(int index) async {
    if (_isRecording) await _stopRecording();
    if (_isPlayingRecord) await _stopPlayback();
    if (_isPlayingTts) await _stopTts();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: _blue,
          foregroundColor: Colors.white,
          title: const Text('발음 녹음'),
          elevation: 0,
        ),
        body: const Center(
          child: Text('단어가 없어요!',
              style: TextStyle(fontSize: 16, color: Colors.black45)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text(
            '발음 녹음 · ${widget.person}   ${_currentIndex + 1}/${_entries.length}'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // 진행 바
          LinearProgressIndicator(
            value: (_currentIndex + 1) / _entries.length,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(_lightBlue),
            minHeight: 4,
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 단어 카드
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        vertical: 40, horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          _current['word']!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _current['meaning']!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // TTS 버튼
                  _ActionButton(
                    icon: _isPlayingTts
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    label: _isPlayingTts ? '재생 중지' : '원어민 발음 듣기',
                    color: _lightBlue,
                    onTap: _isPlayingTts ? _stopTts : _playTts,
                  ),

                  const SizedBox(height: 16),

                  // 녹음 버튼
                  _RecordButton(
                    isRecording: _isRecording,
                    onStart: _startRecording,
                    onStop: _stopRecording,
                  ),

                  const SizedBox(height: 16),

                  // 내 발음 듣기
                  _ActionButton(
                    icon: _isPlayingRecord
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                    label: _isPlayingRecord
                        ? '재생 중지'
                        : _hasRecording
                            ? '내 발음 듣기'
                            : '아직 녹음 없음',
                    color: _hasRecording ? const Color(0xFF43A047) : Colors.grey,
                    onTap: _hasRecording
                        ? (_isPlayingRecord ? _stopPlayback : _playRecording)
                        : null,
                  ),

                  const SizedBox(height: 40),

                  // 이전 / 다음 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _currentIndex > 0
                              ? () => _goTo(_currentIndex - 1)
                              : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _blue,
                            side: BorderSide(
                                color: _currentIndex > 0
                                    ? _blue
                                    : Colors.grey.shade300),
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('← 이전',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _currentIndex < _entries.length - 1
                              ? () => _goTo(_currentIndex + 1)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _currentIndex <
                                    _entries.length - 1
                                ? _blue
                                : Colors.grey.shade300,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('다음 →',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // 단어 목록 (인덱스 이동)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '전체 단어',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(_entries.length, (i) {
                            final done = _recordPaths.containsKey(i);
                            final isCurrent = i == _currentIndex;
                            return GestureDetector(
                              onTap: () => _goTo(i),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isCurrent
                                      ? _blue
                                      : done
                                          ? const Color(0xFFE8F5E9)
                                          : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isCurrent
                                        ? _blue
                                        : done
                                            ? const Color(0xFF43A047)
                                            : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (done && !isCurrent)
                                      const Icon(Icons.mic,
                                          size: 12,
                                          color: Color(0xFF43A047)),
                                    if (done && !isCurrent)
                                      const SizedBox(width: 4),
                                    Text(
                                      _entries[i]['word']!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: isCurrent
                                            ? Colors.white
                                            : done
                                                ? const Color(0xFF2E7D32)
                                                : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 완료 요약
                  Text(
                    '${_recordPaths.length} / ${_entries.length}개 녹음 완료',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
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
}

// ── 액션 버튼 ────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label,
            style:
                const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          foregroundColor: onTap != null ? color : Colors.grey,
          side: BorderSide(color: onTap != null ? color : Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

// ── 녹음 버튼 ─────────────────────────────────────────────────────────────────

class _RecordButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onStart;
  final VoidCallback onStop;

  const _RecordButton({
    required this.isRecording,
    required this.onStart,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRecording ? onStop : onStart,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isRecording ? const Color(0xFFFFEBEE) : const Color(0xFFC62828),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFC62828),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isRecording ? Icons.stop : Icons.mic,
              color: isRecording ? const Color(0xFFC62828) : Colors.white,
              size: 26,
            ),
            const SizedBox(width: 10),
            Text(
              isRecording ? '녹음 중... (탭하면 중지)' : '녹음 시작',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isRecording ? const Color(0xFFC62828) : Colors.white,
              ),
            ),
            if (isRecording) ...[
              const SizedBox(width: 10),
              _PulsingDot(),
            ],
          ],
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Color(0xFFC62828),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
