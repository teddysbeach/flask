import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/app_error.dart';
import '../../core/bootstrap.dart';
import '../../core/routes.dart';
import '../../data/worksheet_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import 'notification_prefs.dart';

/// 받은 알림 목록.
///
/// 알림을 담는 서버 테이블이 아직 없다. 그래서 **예약한 알림을 기기에 적어 두고**
/// 발송 시각이 지난 것을 여기서 보여 준다(최근 50개). 로컬 알림이라 이 기록이 곧 실제 발송이다.
/// 알림을 밀어서 지웠거나 못 본 사용자가 "무슨 문제였더라"를 되찾는 유일한 길이라 목록이 필요하다.
class NotificationListScreen extends ConsumerStatefulWidget {
  const NotificationListScreen({super.key});

  @override
  ConsumerState<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends ConsumerState<NotificationListScreen> {
  String? _opening;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final prefsAsync = ref.watch(sharedPrefsProvider);

    return Scaffold(
      backgroundColor: p.surfaceBase,
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          prefsAsync.maybeWhen(
            data: (raw) {
              final prefs = NotificationPrefs(raw);
              final unread = prefs.unreadCount;
              return TextButton(
                onPressed: unread == 0 ? null : () => _markAllRead(prefs),
                child: const Text('모두 읽음'),
              );
            },
            orElse: () => const SizedBox(width: DsSpace.s4),
          ),
        ],
      ),
      body: SafeArea(
        child: prefsAsync.when(
          loading: () => const LoadingView(),
          error: (e, st) => ErrorView(
            error: AppError.from(e, st),
            onRetry: () => ref.invalidate(sharedPrefsProvider),
          ),
          data: (raw) {
            final prefs = NotificationPrefs(raw);
            final items = prefs.delivered();
            if (items.isEmpty) {
              return const EmptyView(
                title: '아직 받은 알림이 없어요',
                description: '복습할 때가 되면 문제를 알림으로 보내 드릴게요.',
                icon: DsIcons.review,
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: DsSpace.s2),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final entry = items[i];
                return _NotificationTile(
                  entry: entry,
                  busy: _opening == entry.scheduleId,
                  onTap: () => _open(prefs, entry),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _markAllRead(NotificationPrefs prefs) async {
    await prefs.markAllRead();
    if (mounted) setState(() {});
  }

  Future<void> _open(NotificationPrefs prefs, NotificationLogEntry entry) async {
    if (_opening != null) return;
    await prefs.markRead(entry.id);
    if (!mounted) return;
    setState(() => _opening = entry.scheduleId);

    try {
      // 학습지가 아직 있는지 먼저 본다. 없는 화면으로 보내 놓고 거기서 오류를 만나게 하면
      // 사용자는 "앱이 고장났다"고 읽는다.
      await ref.read(worksheetRepositoryProvider).get(entry.worksheetId);
      if (!mounted) return;
      unawaited(context.push('${Routes.worksheet(entry.worksheetId)}?quizId=${entry.quizItemId}'));
    } on AppError catch (e) {
      if (!mounted) return;
      AppFeedback.toast(
        context,
        e.kind == AppErrorKind.notFound ? '이미 지워진 학습지예요.' : e.message,
        danger: e.kind != AppErrorKind.notFound,
      );
    } catch (e, st) {
      if (mounted) AppFeedback.toast(context, AppError.from(e, st).message, danger: true);
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.entry, required this.busy, required this.onTap});

  final NotificationLogEntry entry;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final unread = !entry.read;

    return Semantics(
      button: true,
      label: '${unread ? '안 읽음, ' : ''}${entry.title}',
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 색만으로 안 읽음을 말하지 않는다 — 점과 글자를 같이 쓴다.
              Padding(
                padding: const EdgeInsets.only(top: DsSpace.s1),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: unread ? p.brandPrimary : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: DsSpace.s3),
              Expanded(
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.title,
                              style: dsTextStyle(DsType.bodyLg, p.textPrimary)
                                  .copyWith(fontWeight: unread ? FontWeight.w700 : FontWeight.w400),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: DsSpace.s2),
                            Text('안 읽음', style: dsTextStyle(DsType.caption, p.brandText)),
                          ],
                        ],
                      ),
                      const SizedBox(height: DsSpace.s1),
                      Text(entry.body, style: dsTextStyle(DsType.body, p.textSecondary)),
                      const SizedBox(height: DsSpace.s1),
                      Text(_when(entry.deliverAt),
                          style: dsTextStyle(DsType.caption, p.textTertiary)),
                    ],
                  ),
                ),
              ),
              if (busy) ...[
                const SizedBox(width: DsSpace.s3),
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: p.brandPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${at.year}년 ${at.month}월 ${at.day}일';
  }
}
