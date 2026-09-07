import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/purchase_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';

/// 구매 내역. 결제 문의의 절반은 "내가 산 게 맞나" 라서, 그걸 사용자가 직접 볼 수 있게 둔다.
final purchaseHistoryProvider = FutureProvider<List<PurchaseRecord>>(
  (ref) => ref.watch(purchaseRepositoryProvider).history(),
);

class PurchaseHistoryScreen extends ConsumerWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(purchaseHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('구매 내역'),
        actions: [
          TextButton(
            onPressed: () => unawaited(_restore(context, ref)),
            child: const Text('구매 복원'),
          ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          loading: () => const LoadingView(label: '구매 내역을 불러오는 중'),
          error: (e, st) => ErrorView(
            error: AppError.from(e, st),
            onRetry: () => ref.invalidate(purchaseHistoryProvider),
            onSecondary: () => context.push(Routes.support),
            secondaryLabel: '고객센터로 문의하기',
          ),
          data: (rows) => rows.isEmpty
              ? EmptyView(
                  icon: DsIcons.library,
                  title: '아직 구매한 내역이 없어요',
                  description: '학습지를 충전하면 여기에 남아요.',
                  actionLabel: '충전하러 가기',
                  onAction: () => context.push(Routes.paywall),
                )
              : RefreshIndicator(
                  onRefresh: () async => ref.invalidate(purchaseHistoryProvider),
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: DsSpace.s12),
                    children: [
                      for (final row in rows) _HistoryTile(record: row),
                      Padding(
                        padding: const EdgeInsets.all(DsSpace.s6),
                        child: NoticeBox(
                          text: '결제했는데 장수가 안 늘었다면 "구매 복원" 을 눌러 주세요. '
                              '그래도 그대로면 고객센터로 알려 주세요. 저희가 확인해 드릴게요.',
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(purchaseRepositoryProvider).restorePurchases();
      if (!context.mounted) return;
      AppFeedback.toast(context, '복원할 결제가 있으면 곧 반영돼요.');
      ref.invalidate(purchaseHistoryProvider);
    } on AppError catch (e) {
      if (!context.mounted) return;
      AppFeedback.toast(context, e.message, danger: true);
    }
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});
  final PurchaseRecord record;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final date = DateFormat('yyyy.MM.dd HH:mm').format(record.purchasedAt);
    final price = record.priceKrw == null
        ? null
        : NumberFormat.currency(symbol: '₩', decimalDigits: 0).format(record.priceKrw);

    return Container(
      margin: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s3, DsSpace.s4, 0),
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Semantics(
        container: true,
        label: '${record.sheets}장 충전, $date'
            '${price == null ? '' : ', $price'}'
            '${record.isRefunded ? ', 환불됨' : ''}',
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text('학습지 ${record.sheets}장',
                        style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
                  ),
                  if (price != null)
                    Text(price, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
                ],
              ),
              const SizedBox(height: DsSpace.s1),
              Row(
                children: [
                  Expanded(child: Text(date, style: dsTextStyle(DsType.caption, p.textTertiary))),
                  // 환불 여부를 색이 아니라 아이콘 + 글자로 보여준다.
                  if (record.isRefunded)
                    Row(
                      children: [
                        DsIcon(DsIcons.undo, size: 14, color: p.statusWarning),
                        const SizedBox(width: DsSpace.s1),
                        Text('환불됨', style: dsTextStyle(DsType.caption, p.statusWarning)),
                      ],
                    )
                  else
                    Row(
                      children: [
                        DsIcon(DsIcons.success, size: 14, color: p.statusSuccess),
                        const SizedBox(width: DsSpace.s1),
                        Text('충전 완료', style: dsTextStyle(DsType.caption, p.statusSuccess)),
                      ],
                    ),
                ],
              ),
              if (record.isRefunded) ...[
                const SizedBox(height: DsSpace.s2),
                Text(
                  '환불된 만큼 남은 장수에서 빠졌어요. 이미 만든 학습지는 그대로 볼 수 있어요.',
                  style: dsTextStyle(DsType.caption, p.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
