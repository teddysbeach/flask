import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/env.dart';
import '../../core/routes.dart';
import '../../data/support_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/adaptive.dart';
import 'contact_screen.dart';

/// 내가 보낸 문의와 받은 답.
///
/// 여태 접수 번호를 받고도 그것으로 할 수 있는 일이 없었다. 서버에는 본인만 읽는 정책이
/// 진작 있었는데 보는 화면이 없었다 — **문의는 보내는 것이 아니라 답을 받는 것**이라,
/// 답을 볼 곳이 없으면 절반만 만든 기능이다.
class TicketListScreen extends ConsumerWidget {
  const TicketListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);
    final tickets = ref.watch(myTicketsProvider);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(title: const Text('내 문의')),
      body: SafeArea(
        child: RefreshIndicator(
          color: p.brandText,
          onRefresh: () async => ref.invalidate(myTicketsProvider),
          child: dsAsync(
            tickets,
            loading: () => ListView(
              padding: const EdgeInsets.all(DsSpace.s4),
              children: const [
                SkeletonBox(height: 96),
                SizedBox(height: DsSpace.s2),
                SkeletonBox(height: 96),
              ],
            ),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(myTicketsProvider),
            ),
            data: (items) {
              if (items.isEmpty) {
                return _Scrollable(
                  child: EmptyView(
                    icon: DsIcons.guide,
                    title: '보낸 문의가 없어요',
                    description: '로그인하지 않고 보낸 문의는 계정에 붙지 않아서 여기 나오지 않아요.',
                    actionLabel: '문의하기',
                    onAction: () => context.push(Routes.contact),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                    DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: DsSpace.s2),
                itemBuilder: (context, i) => DsFadeSlide(
                  delay: dsStaggerDelay(i),
                  child: ReadableWidth(child: _TicketCard(ticket: items[i])),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: child,
          ),
        ),
      );
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket});
  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final label = ContactTopic.values
        .firstWhere((t) => t.name == ticket.topic, orElse: () => ContactTopic.other)
        .label;

    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: ticket.answered ? p.statusSuccess : p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: dsTextStyle(DsType.body, p.textPrimary)
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              _StatusBadge(answered: ticket.answered, status: ticket.status),
            ],
          ),
          const SizedBox(height: DsSpace.s1),
          // 접수 번호는 문의 직후 화면에 보여준 것과 같아야 한다. 다르면 사용자는
          // 자기가 적어 둔 번호로 아무것도 못 한다.
          Text('접수 번호 ${ticket.shortId} · ${_when(ticket.createdAt)}',
              style: dsTextStyle(DsType.caption, p.textTertiary)),
          const SizedBox(height: DsSpace.s3),
          Text(ticket.body, style: dsTextStyle(DsType.body, p.textSecondary)),

          if (ticket.answered) ...[
            const SizedBox(height: DsSpace.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DsSpace.s3),
              decoration: BoxDecoration(
                color: p.statusBgSuccess,
                borderRadius: BorderRadius.circular(DsRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('답변',
                      style: dsTextStyle(DsType.caption, p.statusSuccess)
                          .copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: DsSpace.s1),
                  Text(ticket.answer!, style: dsTextStyle(DsType.body, p.textPrimary)),
                  if (ticket.answeredAt != null) ...[
                    const SizedBox(height: DsSpace.s2),
                    Text(_when(ticket.answeredAt!),
                        style: dsTextStyle(DsType.caption, p.textTertiary)),
                  ],
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: DsSpace.s3),
            // 언제까지 기다려야 하는지 말해 준다. 안 말하면 하루 뒤에 같은 문의가 또 온다.
            Text('영업일 기준 2일 안에 ${Env.supportEmail} 로 답을 보내 드려요.',
                style: dsTextStyle(DsType.caption, p.textTertiary)),
          ],
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.answered, required this.status});
  final bool answered;
  final String status;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    // 색만으로 말하지 않는다 — 글자가 같이 간다.
    final (bg, fg, text) = answered
        ? (p.statusBgSuccess, p.statusSuccess, '답변 완료')
        : status == 'closed'
            ? (p.surfaceSunken, p.textTertiary, '종료')
            : (p.statusBgInfo, p.statusInfo, '접수됨');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s2, vertical: DsSpace.s1),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(DsRadius.full)),
      child: Text(text, style: dsTextStyle(DsType.caption, fg)),
    );
  }
}

String _when(DateTime at) =>
    '${at.year}.${at.month.toString().padLeft(2, '0')}.${at.day.toString().padLeft(2, '0')}';
