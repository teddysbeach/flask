/// 결제 화면이 쓰는 상태.
///
/// 상품 정보는 두 곳에서 온다. **장수와 정렬은 서버**(`products`), **가격은 스토어**.
/// 가격을 서버나 앱에 두면 나라·통화·프로모션에 따라 실제 결제 금액과 갈라지고,
/// "표시 가격과 청구 금액이 다르다" 는 스토어 심사 반려 사유가 된다.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../data/profile_repository.dart';
import '../../data/purchase_repository.dart';
import '../../domain/models.dart';

class PaywallOffer {
  const PaywallOffer({required this.catalog, this.store});

  /// 서버가 아는 것: 상품 ID, 장수, 정렬.
  final Product catalog;

  /// 스토어가 아는 것: 표시 가격. 못 불러왔으면 null 이다.
  final ProductDetails? store;

  bool get purchasable => store != null;

  /// 장당 단가. 스토어가 준 실제 금액에서 계산한다 — 앱이 아는 숫자로 만들지 않는다.
  double? get perSheetRaw {
    final s = store;
    if (s == null || catalog.sheets <= 0) return null;
    return s.rawPrice / catalog.sheets;
  }
}

class PaywallData {
  const PaywallData({
    required this.offers,
    required this.storeAvailable,
    required this.missingIds,
  });

  final List<PaywallOffer> offers;

  /// 스토어에 연결 자체가 안 됐다(시뮬레이터, 스토어 로그아웃, 결제 제한).
  final bool storeAvailable;

  /// 스토어가 모른다고 답한 상품 ID. 심사 전에는 여기가 비지 않는 게 정상이다.
  final List<String> missingIds;

  bool get anyPurchasable => offers.any((o) => o.purchasable);
}

/// 가장 인기 배지를 붙일 상품. 하나만 붙는다 — 셋 다 강조하면 아무것도 강조하지 않는 것과 같다.
const kPopularProductId = kProductIdSheets10;

final paywallDataProvider = FutureProvider<PaywallData>((ref) async {
  final catalog = await ref.watch(profileRepositoryProvider).products();
  final purchases = ref.watch(purchaseRepositoryProvider);

  final available = await purchases.isStoreAvailable();
  if (!available) {
    return PaywallData(
      offers: [for (final c in catalog) PaywallOffer(catalog: c)],
      storeAvailable: false,
      missingIds: catalog.map((c) => c.id).toList(),
    );
  }

  final details = await purchases.load(catalog.map((c) => c.id).toSet());
  final byId = {for (final d in details) d.id: d};

  return PaywallData(
    offers: [
      for (final c in catalog) PaywallOffer(catalog: c, store: byId[c.id]),
    ],
    storeAvailable: true,
    missingIds: catalog.map((c) => c.id).where((id) => !byId.containsKey(id)).toList(),
  );
});

/// 결제 진행 상황. 화면이 열려 있는 동안만 듣는다.
final purchaseEventsProvider = StreamProvider<PurchaseEvent>(
  (ref) => ref.watch(purchaseRepositoryProvider).events,
);
