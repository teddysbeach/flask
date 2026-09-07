import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/analytics.dart';
import '../../core/app_error.dart';
import '../../core/routes.dart';
import '../../data/profile_repository.dart';
import '../../data/purchase_repository.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';
import 'paywall_controller.dart';

/// 학습지 충전.
///
/// 여기서 파는 것은 **새 학습지를 만드는 권리**뿐이다. 이미 만든 학습지의 열람·필기·
/// 복습 알림은 결제와 무관하게 계속 무료다 — 그 사실을 화면에서 말해 준다.
/// 결제한 사람만 자기 필기를 볼 수 있는 앱은 만들지 않는다.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  String? _busyProductId;
  bool _restoring = false;

  /// 결제 화면 조회는 한 번만 센다. build 는 상품이 로드될 때마다 다시 불린다.
  bool _viewTracked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewTracked) return;
    _viewTracked = true;
    ref.read(analyticsProvider).track(AnalyticsEvent.paywallView, props: {'from': _entryPoint()});
  }

  /// 어디서 들어왔는지. **부르는 쪽이 아니라 이 화면이** 한 번만 쏜다 —
  /// 진입 지점마다 이벤트를 쏘면 결제 화면 조회 수가 경로 수만큼 부풀려진다.
  ///
  /// 딥링크로도 들어올 수 있으니 값은 우리가 아는 모양만 통과시킨다.
  /// 바깥에서 넣은 문자열이 그대로 분석 도구에 쌓이게 두지 않는다.
  String _entryPoint() {
    String? raw;
    try {
      raw = GoRouterState.of(context).uri.queryParameters['from'];
    } catch (_) {
      raw = null;
    }
    if (raw == null || raw.isEmpty) return 'direct';
    return RegExp(r'^[a-z][a-z0-9_]{0,23}$').hasMatch(raw) ? raw : 'other';
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final data = ref.watch(paywallDataProvider);

    ref.listen(purchaseEventsProvider, (_, next) {
      final event = next.valueOrNull;
      if (event != null) _onPurchaseEvent(event);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('학습지 충전'),
        actions: [
          TextButton(
            onPressed: _restoring ? null : () => unawaited(_restore()),
            child: Text(_restoring ? '복원 중' : '구매 복원'),
          ),
        ],
      ),
      body: SafeArea(
        child: dsAsync(data,
          loading: () => const LoadingView(label: '상품을 불러오는 중'),
          error: (e, st) => ErrorView(
            error: AppError.from(e, st),
            onRetry: () => ref.invalidate(paywallDataProvider),
            onSecondary: () => unawaited(_restore()),
            secondaryLabel: '구매 복원',
          ),
          data: (d) => _body(d, p),
        ),
      ),
    );
  }

  Widget _body(PaywallData d, DsPalette p) {
    final remaining = ref.watch(profileProvider).valueOrNull?.quotaRemaining;

    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
      children: [
        if (remaining != null)
          Semantics(
            liveRegion: true,
            child: Text(
              '지금 남은 학습지 $remaining장',
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
          ),
        const SizedBox(height: DsSpace.s2),
        Text('필요한 만큼만 충전해요', style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s2),
        Text(
          '구독이 아니에요. 한 번 사면 없어질 때까지 쓰고, 다 쓰면 그때 다시 사면 돼요.',
          style: dsTextStyle(DsType.body, p.textSecondary),
        ),
        const SizedBox(height: DsSpace.s6),

        // 스토어에서 상품을 못 불러온 경우. 없는 척하지 않고 그대로 말한다.
        if (!d.storeAvailable) ...[
          const NoticeBox(
            tone: NoticeTone.warning,
            title: '지금은 결제할 수 없어요',
            text: '이 기기에서 앱스토어에 연결하지 못했어요. 스토어 로그인 상태와 결제 제한 설정을 확인한 뒤 '
                '다시 시도해 주세요.',
          ),
          const SizedBox(height: DsSpace.s4),
        ] else if (!d.anyPurchasable) ...[
          const NoticeBox(
            tone: NoticeTone.warning,
            title: '상품 정보를 못 받았어요',
            text: '스토어가 아직 이 상품들을 모른다고 답했어요. 저희 쪽 준비가 덜 됐을 수 있어요. '
                '잠시 뒤에 다시 시도해 주시고, 계속 이러면 고객센터로 알려 주세요.',
          ),
          const SizedBox(height: DsSpace.s4),
        ] else if (d.missingIds.isNotEmpty) ...[
          const NoticeBox(
            tone: NoticeTone.info,
            text: '일부 상품을 지금은 살 수 없어요. 나머지는 그대로 구매할 수 있어요.',
          ),
          const SizedBox(height: DsSpace.s4),
        ],

        if (d.offers.isEmpty)
          EmptyView(
            title: '보여드릴 상품이 없어요',
            description: '잠시 뒤에 다시 시도해 주세요.',
            actionLabel: '다시 시도',
            onAction: () => ref.invalidate(paywallDataProvider),
          )
        else
          for (final offer in d.offers) ...[
            _OfferCard(
              offer: offer,
              popular: offer.catalog.id == kPopularProductId,
              busy: _busyProductId == offer.catalog.id,
              disabled: _busyProductId != null,
              onBuy: () => unawaited(_buy(offer)),
            ),
            const SizedBox(height: DsSpace.s3),
          ],

        const SizedBox(height: DsSpace.s4),
        OutlinedButton(
          onPressed: _restoring ? null : () => unawaited(_restore()),
          child: Text(_restoring ? '복원 중' : '구매 복원'),
        ),
        const SizedBox(height: DsSpace.s6),
        const _RefundPolicy(),
        const SizedBox(height: DsSpace.s4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(onPressed: () => context.push(Routes.terms), child: const Text('이용약관')),
            TextButton(
              onPressed: () => context.push(Routes.privacy),
              child: const Text('개인정보처리방침'),
            ),
            TextButton(onPressed: () => context.push(Routes.support), child: const Text('고객센터')),
          ],
        ),
      ],
    );
  }

  Future<void> _buy(PaywallOffer offer) async {
    final store = offer.store;
    if (store == null) return;
    setState(() => _busyProductId = offer.catalog.id);
    // 상품 id 는 우리가 정한 고정 문자열이다(가격·영수증은 싣지 않는다).
    ref.read(analyticsProvider)
        .track(AnalyticsEvent.purchaseStart, props: {'product_id': offer.catalog.id});
    await ref.read(purchaseRepositoryProvider).buy(store);
    // 여기서 끝이 아니다 — 결과는 purchaseEventsProvider 로 온다.
    // 결제창이 뜬 뒤 앱이 죽어도 다음 실행에서 스트림이 그 거래를 다시 들고 온다.
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    ref.read(analyticsProvider).track(AnalyticsEvent.purchaseRestore);
    try {
      await ref.read(purchaseRepositoryProvider).restorePurchases();
      if (!mounted) return;
      AppFeedback.toast(context, '복원할 결제가 있으면 곧 반영돼요.');
    } on AppError catch (e) {
      if (!mounted) return;
      AppFeedback.toast(context, e.message, danger: true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _onPurchaseEvent(PurchaseEvent event) {
    if (!mounted) return;
    switch (event.phase) {
      case PurchasePhase.pending:
        setState(() => _busyProductId = event.productId);
      case PurchasePhase.granted:
        setState(() => _busyProductId = null);
        ref.invalidate(profileProvider);
        AppFeedback.toast(context, '${event.granted}장을 충전했어요.');
      case PurchasePhase.alreadyOwned:
        setState(() => _busyProductId = null);
        ref.invalidate(profileProvider);
        AppFeedback.toast(context, '이미 반영된 결제예요. 남은 장수를 확인해 주세요.');
      case PurchasePhase.cancelled:
        // 취소는 오류가 아니다. 빨간 토스트를 띄우지 않는다.
        setState(() => _busyProductId = null);
        AppFeedback.toast(context, '결제를 취소했어요.');
      case PurchasePhase.failed:
        setState(() => _busyProductId = null);
        AppFeedback.toast(
          context,
          event.error?.message ?? '결제를 끝내지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
          danger: true,
        );
    }
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.popular,
    required this.busy,
    required this.disabled,
    required this.onBuy,
  });

  final PaywallOffer offer;
  final bool popular;
  final bool busy;
  final bool disabled;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final store = offer.store;
    final sheets = offer.catalog.sheets;
    final price = store?.price;
    final perSheet = _formatPerSheet(offer);

    return Semantics(
      container: true,
      button: true,
      enabled: store != null && !disabled,
      label: [
        '학습지 $sheets장',
        if (popular) '가장 인기 있는 상품',
        if (price != null) price,
        if (perSheet != null) '한 장에 $perSheet',
        if (store == null) '지금은 살 수 없어요',
      ].join(', '),
      child: ExcludeSemantics(
        // 상품 카드는 값을 스토어에서 받아 채운다. 가격이 늦게 들어와 테두리·배지가
        // 툭 바뀌면 "값이 바뀌었나" 로 읽힌다 — 돈 이야기에서 그건 특히 나쁘다.
        child: AnimatedContainer(
          duration: dsDuration(context, DsMotion.base),
          curve: DsCurve.standard,
          padding: const EdgeInsets.all(DsSpace.s4),
          decoration: BoxDecoration(
            color: p.surfaceRaised,
            borderRadius: BorderRadius.circular(DsRadius.lg),
            border: Border.all(
              color: popular ? p.brandText : p.borderSubtle,
              width: popular ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: DsSpace.s2,
                      runSpacing: DsSpace.s1,
                      children: [
                        Text('$sheets장', style: dsTextStyle(DsType.h2, p.textPrimary)),
                        // 배지는 색만이 아니라 글자로도 뜻을 말한다.
                        if (popular)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: DsSpace.s2,
                              vertical: DsSpace.s1,
                            ),
                            decoration: BoxDecoration(
                              color: p.brandPrimarySubtle,
                              borderRadius: BorderRadius.circular(DsRadius.full),
                            ),
                            child: Text(
                              '가장 인기',
                              style: dsTextStyle(DsType.caption, p.brandTextOnSubtle),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DsSpace.s3),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        // 가격은 언제나 스토어가 준 문자열 그대로. 앱이 숫자를 만들지 않는다.
                        price ?? '가격을 못 받았어요',
                        style: dsTextStyle(DsType.h3, p.textPrimary),
                      ),
                      if (perSheet != null)
                        Text('한 장에 $perSheet', style: dsTextStyle(DsType.caption, p.textTertiary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: DsSpace.s4),
              SizedBox(
                width: double.infinity,
                child: DsPressable(
                  enabled: store != null && !disabled,
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: store == null || disabled ? null : onBuy,
                    // 결제창이 뜨기까지의 몇 초. 글자가 스피너로 툭 바뀌면
                    // 눌린 건지 실패한 건지 알 수 없다.
                    child: DsSwitcher(
                      duration: DsMotion.fast,
                      alignment: Alignment.center,
                      travel: 0,
                      child: busy
                          ? SizedBox(
                              key: const ValueKey('busy'),
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: p.brandOnPrimary,
                              ),
                            )
                          : Text(store == null ? '지금은 살 수 없어요' : '구매하기',
                              key: const ValueKey('label')),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _formatPerSheet(PaywallOffer offer) {
    final raw = offer.perSheetRaw;
    final store = offer.store;
    if (raw == null || store == null) return null;
    // 소수점 자리는 통화가 정한다 — 원화에 소수점을 찍으면 가짜 정밀도가 된다.
    final zeroDecimal = {'KRW', 'JPY', 'VND', 'CLP', 'ISK'}.contains(store.currencyCode);
    final symbol = store.currencySymbol.isEmpty ? store.currencyCode : store.currencySymbol;
    return NumberFormat.currency(symbol: symbol, decimalDigits: zeroDecimal ? 0 : 2).format(raw);
  }
}

/// 환불·청약철회 안내. 소모성 상품이라 "구매 즉시 제공" 에 해당하므로 그 사실을 먼저 말한다.
class _RefundPolicy extends StatelessWidget {
  const _RefundPolicy();

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(DsSpace.s4),
      decoration: BoxDecoration(
        color: p.surfaceSunken,
        borderRadius: BorderRadius.circular(DsRadius.md),
        border: Border.all(color: p.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('환불과 취소', style: dsTextStyle(DsType.body, p.textPrimary).copyWith(
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: DsSpace.s2),
          for (final line in const [
            '결제하면 장수가 바로 들어와요. 아직 안 쓴 장수는 환불받을 수 있어요.',
            '이미 쓴 장수는 돌려받을 수 없어요. 대신 만들다 실패한 학습지는 자동으로 되돌려 드려요.',
            '환불은 애플·구글 스토어에서 신청해요. 처리되면 남은 장수에서 그만큼 빠져요.',
            '이미 만든 학습지는 환불 뒤에도 계속 볼 수 있어요. 필기도 그대로예요.',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpace.s1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('· ', style: dsTextStyle(DsType.body, p.textSecondary)),
                  Expanded(child: Text(line, style: dsTextStyle(DsType.body, p.textSecondary))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
