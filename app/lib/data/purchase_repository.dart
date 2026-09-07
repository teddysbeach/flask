/// 인앱결제. 스토어와 우리 서버 사이에서 앱이 하는 일은 셋뿐이다 —
/// **상품을 보여주고, 결제를 띄우고, 영수증을 서버로 넘긴다.**
///
/// 쿼터를 늘리는 것은 앱이 아니라 서버다. 앱이 늘릴 수 있으면 앱을 뜯어 고친 사람이
/// 무한히 늘릴 수 있다는 뜻이고, 그 순간 결제는 장식이 된다.
/// 그래서 이 파일 어디에도 "장수를 더한다" 는 코드가 없다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_error.dart';
import '../core/logger.dart';
import 'supabase.dart';

/// 스토어에 올라간 상품 ID. 서버 `products` 테이블의 id 와 같은 문자열이다.
/// (가격은 여기에 없다 — 가격은 언제나 스토어가 준 문자열을 그대로 쓴다.)
const kProductIdSheets3 = 'onpar.sheets.3';
const kProductIdSheets10 = 'onpar.sheets.10';
const kProductIdSheets30 = 'onpar.sheets.30';

/// 결제 한 건을 처리한 뒤 앱이 다음에 할 일.
enum PurchaseAction {
  /// 서버 검증을 부른다.
  verify,

  /// 아직 끝나지 않았다(가족 승인 대기 등). 기다린다.
  wait,

  /// 사용자가 스스로 닫았다. 오류가 아니다.
  cancelled,

  /// 실패했다.
  failed,
}

/// 스토어가 준 구매 결과를 읽은 결론.
///
/// 이 타입이 따로 있는 이유: 스토어 결과 → 서버 요청 본문으로 옮기는 규칙은
/// 틀리면 돈이 새는데(중복 지급·미지급), 스트림 안에 섞여 있으면 테스트할 수가 없다.
class PurchaseVerdict {
  const PurchaseVerdict({
    required this.action,
    this.body,
    this.complete = false,
    this.error,
  });

  final PurchaseAction action;

  /// `verify-purchase` 에 보낼 본문. `action == verify` 일 때만 있다.
  final Map<String, Object?>? body;

  /// 지금 `completePurchase` 를 불러야 하는가.
  ///
  /// 검증이 필요한 건은 여기서 false 다 — 검증이 끝난 뒤에 부른다.
  /// 먼저 부르면 스토어가 거래를 닫아버려서, 검증이 실패했을 때 다시 받을 방법이 없다.
  final bool complete;

  /// 사용자에게 보여줄 실패. `action` 이 cancelled/failed 일 때만 있다.
  final AppError? error;
}

/// **순수 함수.** 스토어 결과 → 서버 검증 요청 본문.
///
/// 플랫폼을 인자로 받는 이유는 테스트 때문만이 아니다. `Platform.isIOS` 를
/// 안에서 읽으면 iOS 에서 산 영수증을 안드로이드 규칙으로 보내는 실수를
/// 실기기에서만 발견하게 된다.
///
/// `transaction_id` 는 **앱이 주장하는 값일 뿐이다.** 서버는 영수증을 직접
/// 검증한 뒤 자기가 읽어낸 거래 ID 를 최종 기준으로 쓴다. 앱 값을 그대로 믿으면
/// 아무 문자열이나 보내서 지급을 요구할 수 있다.
PurchaseVerdict readPurchase(PurchaseDetails purchase, {required String platform}) {
  switch (purchase.status) {
    case PurchaseStatus.pending:
      return const PurchaseVerdict(action: PurchaseAction.wait);

    case PurchaseStatus.canceled:
      // 사용자가 결제창을 닫은 것은 실패가 아니다. 오류 화면을 띄우면 안 된다.
      return PurchaseVerdict(
        action: PurchaseAction.cancelled,
        complete: purchase.pendingCompletePurchase,
        error: AppError.of(AppErrorKind.cancelled),
      );

    case PurchaseStatus.error:
      return PurchaseVerdict(
        action: PurchaseAction.failed,
        complete: purchase.pendingCompletePurchase,
        error: AppError.of(
          AppErrorKind.unknown,
          cause: purchase.error,
          message: '결제를 끝내지 못했어요. 결제된 게 있다면 "구매 복원"으로 되살릴 수 있어요.',
        ),
      );

    case PurchaseStatus.purchased:
    case PurchaseStatus.restored:
      final receipt = purchase.verificationData.serverVerificationData;
      if (receipt.isEmpty) {
        // 영수증 없이 지급을 요청할 수는 없다. 거래는 닫지 않는다 —
        // 스토어가 다시 보내주면 그때 제대로 처리한다.
        return PurchaseVerdict(
          action: PurchaseAction.failed,
          error: AppError.of(
            AppErrorKind.unknown,
            message: '스토어에서 영수증을 받지 못했어요. 잠시 뒤에 "구매 복원"을 눌러 주세요.',
          ),
        );
      }
      return PurchaseVerdict(
        action: PurchaseAction.verify,
        body: {
          'platform': platform,
          'product_id': purchase.productID,
          'transaction_id': transactionIdOf(purchase, platform: platform),
          'receipt': receipt,
        },
      );
  }
}

/// 거래 식별자.
///
/// iOS 는 `purchaseID` 가 transaction identifier 다.
/// 안드로이드는 `purchaseID` 가 orderId 인데 프로모션·테스트 구매에서는 비어 있다 —
/// 그럴 때는 구매 토큰(영수증)을 식별자로 쓴다. 토큰은 구매 한 건당 하나다.
String transactionIdOf(PurchaseDetails purchase, {required String platform}) {
  final id = purchase.purchaseID ?? '';
  if (id.isNotEmpty) return id;
  return purchase.verificationData.serverVerificationData;
}

/// 화면이 구독하는 결제 진행 상황.
enum PurchasePhase { pending, granted, alreadyOwned, cancelled, failed }

class PurchaseEvent {
  const PurchaseEvent(this.phase, {this.productId, this.granted = 0, this.error});

  final PurchasePhase phase;
  final String? productId;

  /// 이번에 늘어난 장수. 서버가 알려준 값이다(앱이 계산하지 않는다).
  final int granted;
  final AppError? error;
}

/// 구매 내역 한 줄. 영수증 원문은 화면에 오지 않는다.
class PurchaseRecord {
  const PurchaseRecord({
    required this.id,
    required this.productId,
    required this.sheets,
    required this.state,
    required this.purchasedAt,
    this.priceKrw,
  });

  final String id;
  final String productId;
  final int sheets;

  /// `granted` | `refunded` | `revoked`
  final String state;
  final DateTime purchasedAt;
  final int? priceKrw;

  bool get isRefunded => state == 'refunded' || state == 'revoked';

  factory PurchaseRecord.fromMap(Map<String, dynamic> m) => PurchaseRecord(
        id: m['id'] as String,
        productId: m['product_id'] as String? ?? '',
        sheets: (m['quantity_granted'] as num?)?.toInt() ?? 0,
        state: m['state'] as String? ?? 'granted',
        purchasedAt:
            DateTime.tryParse('${m['purchased_at'] ?? m['created_at']}')?.toLocal() ?? DateTime.now(),
        priceKrw: (m['price_krw'] as num?)?.toInt(),
      );
}

class PurchaseRepository {
  PurchaseRepository(this._iap, this._client, {required String platform}) : _platform = platform {
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e, StackTrace st) {
        AppLogger.error('purchase stream failed', error: e, stack: st);
        _emit(PurchaseEvent(PurchasePhase.failed, error: AppError.from(e, st)));
      },
    );
  }

  final InAppPurchase _iap;
  final SupabaseClient _client;
  final String _platform;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _events = StreamController<PurchaseEvent>.broadcast();

  /// 결제 진행 상황. 화면은 이것만 본다.
  ///
  /// 스트림인 이유: 앱 밖에서 끝난 결제(가족 승인, 앱을 껐다 켠 사이의 재전달)가
  /// 아무 화면도 열려 있지 않을 때 도착한다. 버튼의 `await` 로는 못 받는다.
  Stream<PurchaseEvent> get events => _events.stream;

  /// 마지막 `load` 에서 스토어가 모른다고 답한 상품 ID.
  /// 심사 전이거나 테스트 기기면 여기가 비지 않는다 — 화면은 그 사실을 정직하게 말한다.
  Set<String> get missingProductIds => Set.unmodifiable(_missing);
  final Set<String> _missing = {};

  Future<bool> isStoreAvailable() async {
    try {
      return await _iap.isAvailable();
    } catch (e, st) {
      AppLogger.error('store availability check failed', error: e, stack: st);
      return false;
    }
  }

  /// 스토어에서 실제 가격을 가져온다.
  ///
  /// **앱에 가격을 박지 않는다.** 나라·통화·스토어 프로모션에 따라 다르고,
  /// 박아두면 앱 업데이트 없이는 못 고친다. 화면에 찍는 것은 언제나 `ProductDetails.price` 다.
  Future<List<ProductDetails>> load(Set<String> ids) async {
    try {
      final res = await _iap.queryProductDetails(ids);
      _missing
        ..clear()
        ..addAll(res.notFoundIDs);
      if (res.error != null && res.productDetails.isEmpty) {
        throw AppError.of(
          AppErrorKind.server,
          cause: res.error,
          message: '스토어에서 상품을 불러오지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
        );
      }
      final sorted = [...res.productDetails]..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
      return sorted;
    } on AppError {
      rethrow;
    } catch (e, st) {
      AppLogger.error('queryProductDetails failed', error: e, stack: st);
      throw AppError.of(
        AppErrorKind.server,
        cause: e,
        message: '스토어에서 상품을 불러오지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
      );
    }
  }

  /// 결제창을 띄운다. 결과는 [events] 로 온다 — 이 Future 는 "창이 떴다" 까지만 책임진다.
  ///
  /// 학습지 팩은 전부 소모성(consumable)이다. 비소모성으로 사면 두 번째 구매가 막힌다.
  Future<void> buy(ProductDetails product) async {
    try {
      final ok = await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: product));
      if (!ok) {
        _emit(PurchaseEvent(
          PurchasePhase.failed,
          productId: product.id,
          error: AppError.of(
            AppErrorKind.unknown,
            message: '결제창을 열지 못했어요. 잠시 뒤에 다시 시도해 주세요.',
          ),
        ));
      }
    } catch (e, st) {
      AppLogger.error('buyConsumable failed', error: e, stack: st);
      _emit(PurchaseEvent(
        PurchasePhase.failed,
        productId: product.id,
        error: AppError.from(e, st),
      ));
    }
  }

  /// 구매 복원. iOS 심사에서 없으면 반려된다.
  ///
  /// 소모성 상품이라 스토어가 돌려주는 건 "아직 안 닫힌 거래" 뿐이다.
  /// 그래도 필요하다 — 결제는 됐는데 검증 도중 앱이 죽은 건이 여기로 돌아온다.
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
    } catch (e, st) {
      AppLogger.error('restorePurchases failed', error: e, stack: st);
      throw AppError.from(e, st);
    }
  }

  Future<List<PurchaseRecord>> history() async {
    try {
      final rows = await _client
          .from('purchases')
          .select('id, product_id, quantity_granted, price_krw, state, purchased_at, created_at')
          .order('purchased_at', ascending: false);
      return rows.map(PurchaseRecord.fromMap).toList();
    } catch (e, st) {
      throw mapSupabaseError(e, st);
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      await _handle(p);
    }
  }

  Future<void> _handle(PurchaseDetails purchase) async {
    final verdict = readPurchase(purchase, platform: _platform);

    if (verdict.action != PurchaseAction.verify) {
      if (verdict.complete) await _complete(purchase);
      switch (verdict.action) {
        case PurchaseAction.wait:
          _emit(PurchaseEvent(PurchasePhase.pending, productId: purchase.productID));
        case PurchaseAction.cancelled:
          _emit(PurchaseEvent(PurchasePhase.cancelled, productId: purchase.productID));
        case PurchaseAction.failed:
          _emit(PurchaseEvent(
            PurchasePhase.failed,
            productId: purchase.productID,
            error: verdict.error,
          ));
        case PurchaseAction.verify:
          break;
      }
      return;
    }

    _emit(PurchaseEvent(PurchasePhase.pending, productId: purchase.productID));

    try {
      final result = await _verify(verdict.body!);
      // 검증이 끝난 뒤에야 거래를 닫는다. 순서를 바꾸면 검증 실패 = 돈만 받고 지급 없음이 된다.
      await _complete(purchase);
      // TODO(analytics): purchaseComplete
      _emit(PurchaseEvent(
        result.alreadyProcessed ? PurchasePhase.alreadyOwned : PurchasePhase.granted,
        productId: purchase.productID,
        granted: result.granted,
      ));
    } on AppError catch (e) {
      // 다시 시도할 여지가 없는 실패(영수증 자체가 가짜)면 거래를 닫는다.
      // 안 닫으면 iOS 가 앱을 켤 때마다 같은 영수증을 계속 재전달한다.
      //
      // 반대로 네트워크·서버 문제라면 **일부러 닫지 않는다.** 스토어가 다시 보내주는 것이
      // 유일한 복구 경로다. 재검증이 두 번 지급되는 일은 없다 —
      // 서버 `purchases` 의 `unique (platform, transaction_id)` 가 막고,
      // `grant_quota_from_purchase` 는 이미 처리된 영수증에 `already_processed` 를 돌려준다.
      if (!e.retryable) await _complete(purchase);
      _emit(PurchaseEvent(PurchasePhase.failed, productId: purchase.productID, error: e));
    }
  }

  Future<({int granted, bool alreadyProcessed})> _verify(Map<String, Object?> body) async {
    try {
      final res = await _client.functions.invoke('verify-purchase', body: body);
      final data = res.data;
      if (data is Map) {
        return (
          granted: (data['granted'] as num?)?.toInt() ?? 0,
          alreadyProcessed: data['already_processed'] == true,
        );
      }
      throw AppError.of(
        AppErrorKind.unknown,
        cause: data,
        message: '결제는 됐는데 확인이 안 끝났어요. 잠시 뒤에 "구매 복원"을 눌러 주세요.',
      );
    } catch (e, st) {
      final mapped = mapSupabaseError(e, st);
      AppLogger.error('verify-purchase failed (${mapped.kind.name})', error: e, stack: st);
      throw mapped;
    }
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(purchase);
    } catch (e, st) {
      // 여기서 실패해도 사용자에게 보여줄 것은 없다. 스토어가 다시 보내고, 서버가 중복을 막는다.
      AppLogger.error('completePurchase failed', error: e, stack: st);
    }
  }

  void _emit(PurchaseEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _events.close();
  }
}

/// 앱이 도는 스토어. 테스트에서는 이 프로바이더만 갈아끼우면 된다.
final purchasePlatformProvider = Provider<String>((ref) {
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
});

final purchaseRepositoryProvider = Provider<PurchaseRepository>((ref) {
  final repo = PurchaseRepository(
    InAppPurchase.instance,
    ref.watch(supabaseProvider),
    platform: ref.watch(purchasePlatformProvider),
  );
  // 스트림 구독이 남으면 결제 결과가 죽은 화면으로 흘러간다.
  ref.onDispose(() => unawaited(repo.dispose()));
  return repo;
});
