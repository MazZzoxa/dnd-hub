import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/import/import_manager.dart';

Future<Map<String, String>?> showImportPreviewDialog(
  BuildContext context, {
  required String sourceLabel,
  required ImportPreview preview,
}) {
  return showDialog<Map<String, String>?> (
    context: context,
    builder: (dialogContext) => ImportPreviewDialog(
      sourceLabel: sourceLabel,
      preview: preview,
    ),
  );
}

class ImportPreviewDialog extends StatefulWidget {
  final String sourceLabel;
  final ImportPreview preview;

  const ImportPreviewDialog({
    super.key,
    required this.sourceLabel,
    required this.preview,
  });

  @override
  State<ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<ImportPreviewDialog> {
  late final Map<String, TextEditingController> _controllers;
  final Set<String> _expandedCollections = <String>{};
  final Set<String> _expandedEntities = <String>{};

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in _allFields(widget.preview))
        field.key: TextEditingController(text: field.value),
    };
  }

  Iterable<ImportPreviewField> _allFields(ImportPreview preview) sync* {
    yield* preview.fields;
    for (final section in preview.sections) {
      for (final entity in section.entities) {
        yield* entity.fields;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String get _title {
    switch (widget.preview.exportType) {
      case 'character':
        return 'Предпросмотр персонажа';
      case 'library':
        return 'Предпросмотр библиотеки';
      case 'libraryItem':
        return 'Предпросмотр объекта';
      default:
        return 'Предпросмотр импорта';
    }
  }

  String get _sourceType {
    final label = widget.sourceLabel.toLowerCase();
    if (label.startsWith('http://') || label.startsWith('https://')) return 'URL';
    if (label.endsWith('.pdf')) return 'PDF';
    if (label.endsWith('.json')) return 'JSON';
    if (label.endsWith('.dndhub')) return 'D&D Hub';
    return 'Файл';
  }

  void _submit() {
    final edited = <String, String>{
      for (final entry in _controllers.entries) entry.key: entry.value.text.trim(),
    };
    Navigator.of(context).pop(edited);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = (size.width * .9).clamp(360.0, 900.0);
    final dialogHeight = size.height < 720 ? size.height * .72 : 660.0;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 16, 10),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
          ),
          Chip(
            label: Text(_sourceType),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: ListView(
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            if (widget.preview.fields.isNotEmpty) ...[
              _PreviewSection(
                title: 'Основные данные',
                child: _buildFieldsGrid(widget.preview.fields),
              ),
              const SizedBox(height: 12),
            ],
            for (final section in widget.preview.sections) ...[
              _buildCollectionSection(section),
              const SizedBox(height: 10),
            ],
            if (widget.preview.warnings.isNotEmpty) ...[
              _buildWarnings(),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            const Text(
              'Здесь можно исправить распознанные данные до импорта. Исходный файл или URL не изменяется.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.download_done),
          label: const Text('Импортировать'),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.preview.imageUrl.trim().isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 7,
              child: Image.network(
                widget.preview.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppTheme.surfaceVariant,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined, size: 32),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          widget.preview.title,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          widget.sourceLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        if (widget.preview.counts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final entry in widget.preview.counts.entries)
                Chip(
                  label: Text('${entry.key}: ${entry.value}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildFieldsGrid(List<ImportPreviewField> fields) {
    final compact = fields.where((field) => !field.multiline).toList();
    final multiline = fields.where((field) => field.multiline).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 660;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final field in compact) SizedBox(width: itemWidth, child: _buildField(field)),
            for (final field in multiline)
              SizedBox(width: constraints.maxWidth, child: _buildField(field)),
          ],
        );
      },
    );
  }

  Widget _buildField(ImportPreviewField field) {
    final controller = _controllers[field.key]!;
    return TextField(
      controller: controller,
      minLines: field.multiline ? 3 : 1,
      maxLines: field.multiline ? 6 : 1,
      decoration: InputDecoration(
        labelText: field.label,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .28),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .18),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.4,
          ),
        ),
        isDense: true,
      ),
      keyboardType: field.multiline ? TextInputType.multiline : TextInputType.text,
    );
  }

  Widget _buildCollectionSection(ImportPreviewSection section) {
    final expanded = _expandedCollections.contains(section.key);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: .2),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 17,
              child: Text('${section.entities.length}'),
            ),
            title: Text(
              section.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(_sectionSubtitle(section)),
            trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            onTap: () {
              setState(() {
                if (expanded) {
                  _expandedCollections.remove(section.key);
                } else {
                  _expandedCollections.add(section.key);
                }
              });
            },
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (final entity in section.entities) ...[
                    _buildEntity(section, entity),
                    if (entity != section.entities.last) const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _sectionSubtitle(ImportPreviewSection section) {
    if (section.entities.isEmpty) return 'Нет объектов';
    final names = section.entities
        .map((entity) => _findController(entity.titleFieldKey).text.trim())
        .where((name) => name.isNotEmpty)
        .take(4)
        .join(', ');
    if (names.isEmpty) return 'Нажмите, чтобы посмотреть данные';
    final suffix = section.entities.length > 4 ? '…' : '';
    return '$names$suffix';
  }

  Widget _buildEntity(ImportPreviewSection section, ImportPreviewEntity entity) {
    final expanded = _expandedEntities.contains(entity.key);
    final titleController = _findController(entity.titleFieldKey);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          ListTile(
            dense: true,
            title: TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Название',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
            trailing: IconButton(
              tooltip: expanded ? 'Свернуть' : 'Подробнее',
              onPressed: () {
                setState(() {
                  if (expanded) {
                    _expandedEntities.remove(entity.key);
                  } else {
                    _expandedEntities.add(entity.key);
                  }
                });
              },
              icon: Icon(expanded ? Icons.expand_less : Icons.more_horiz),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _buildFieldsGrid(
                entity.fields.where((field) => field.key != entity.titleFieldKey).toList(),
              ),
            ),
        ],
      ),
    );
  }

  TextEditingController _findController(String key) => _controllers[key]!;

  Widget _buildWarnings() {
    return _PreviewSection(
      title: 'Что проверить',
      icon: Icons.warning_amber_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final warning in widget.preview.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.circle, size: 6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(warning, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewSection extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;

  const _PreviewSection({
    required this.title,
    required this.child,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: .2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 7),
              ],
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
