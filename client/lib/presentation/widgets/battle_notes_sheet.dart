import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/repositories/battle_notes_repository.dart';

Future<void> showBattleNotesSheet(
  BuildContext context, {
  required String sessionKey,
  required String ownerKey,
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BattleNotesSheet(
      sessionKey: sessionKey,
      ownerKey: ownerKey,
      title: title,
    ),
  );
}

class _BattleNotesSheet extends StatefulWidget {
  final String sessionKey;
  final String ownerKey;
  final String title;

  const _BattleNotesSheet({
    required this.sessionKey,
    required this.ownerKey,
    required this.title,
  });

  @override
  State<_BattleNotesSheet> createState() => _BattleNotesSheetState();
}

class _BattleNotesSheetState extends State<_BattleNotesSheet> {
  final BattleNotesRepository _repository = BattleNotesRepository();
  late final TextEditingController _controller;
  Timer? _saveTimer;
  bool _loading = true;
  bool _saving = false;
  bool _canSave = false;
  bool _closing = false;
  String _saveStatus = 'Заметки хранятся только на этом устройстве';
  int _saveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    try {
      final note = await _repository.getNote(
        sessionKey: widget.sessionKey,
        ownerKey: widget.ownerKey,
      );
      if (!mounted) return;
      _controller.text = note;
      setState(() {
        _loading = false;
        _canSave = true;
        _saveStatus = 'Заметки хранятся только на этом устройстве';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _saveStatus = 'Не удалось загрузить заметки: $error';
      });
    }
  }

  void _onChanged(String value) {
    _canSave = true;
    _saveTimer?.cancel();
    final generation = ++_saveGeneration;
    setState(() {
      _saving = true;
      _saveStatus = 'Сохранение…';
    });
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save(value, generation: generation));
    });
  }

  Future<void> _save(String value, {required int generation}) async {
    try {
      await _repository.saveNote(
        sessionKey: widget.sessionKey,
        ownerKey: widget.ownerKey,
        content: value,
      );
      if (!mounted || generation != _saveGeneration) return;
      setState(() {
        _saving = false;
        _saveStatus = 'Сохранено';
      });
    } catch (error) {
      if (!mounted || generation != _saveGeneration) return;
      setState(() {
        _saving = false;
        _saveStatus = 'Ошибка сохранения: $error';
      });
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    ++_saveGeneration;
    if (_canSave) {
      try {
        await _repository.saveNote(
          sessionKey: widget.sessionKey,
          ownerKey: widget.ownerKey,
          content: _controller.text,
        );
      } catch (_) {
        // The last autosave remains the best available copy if a final write fails.
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    // Flush the latest edit even when the sheet is dismissed by swipe/back.
    _saveTimer?.cancel();
    if (_canSave && !_closing) {
      final generation = ++_saveGeneration;
      unawaited(_save(_controller.text, generation: generation));
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sticky_note_2_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: _close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              TextField(
                controller: _controller,
                autofocus: true,
                minLines: 5,
                maxLines: 12,
                maxLength: 12000,
                decoration: const InputDecoration(
                  hintText: 'Запишите важные события, планы, подсказки…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                onChanged: _onChanged,
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (_saving)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_saving) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _saveStatus,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton(onPressed: _close, child: const Text('Готово')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
