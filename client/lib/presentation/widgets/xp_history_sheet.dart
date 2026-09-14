import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/xp_transaction_model.dart';

Future<void> showXpHistorySheet(BuildContext context, List<XpTransactionModel> items) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('История XP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('История пока пуста.'))
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final sign = item.delta > 0 ? '+' : '';
                      final levelChanged = item.levelBefore != item.levelAfter;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(child: Icon(item.delta > 0 ? Icons.add : Icons.remove)),
                        title: Text('$sign${item.delta} XP'),
                        subtitle: Text('${item.xpBefore} → ${item.xpAfter}${item.reason.isEmpty ? '' : ' · ${item.reason}'}\n${_formatDate(item.createdAt)}'),
                        isThreeLine: true,
                        trailing: levelChanged ? Text('Ур. ${item.levelBefore} → ${item.levelAfter}', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w700)) : null,
                      );
                    },
                  ),
          ),
        ]),
      ),
    ),
  );
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
