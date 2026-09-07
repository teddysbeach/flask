import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:onpar/core/app_error.dart';
import 'package:onpar/data/purchase_repository.dart';

/// 결제 결과 → 서버 검증 요청 본문.
///
/// 이 변환이 틀리면 돈이 샌다. 지급이 안 되거나(사용자가 산 걸 못 받고),
/// 엉뚱한 거래 ID 로 두 번 지급되거나, 취소를 실패로 오해해 오류 화면을 띄운다.
/// 위젯 테스트로는 이 셋을 잡을 수 없어서 순수 함수로 떼어 놓고 여기서 본다.
PurchaseDetails _purchase({
  required PurchaseStatus status,
  String productID = 'onpar.sheets.10',
  String? purchaseID = 'txn-1001',
  String receipt = 'receipt-blob',
  bool pendingComplete = true,
  IAPError? error,
}) {
  final details = PurchaseDetails(
    purchaseID: purchaseID,
    productID: productID,
    verificationData: PurchaseVerificationData(
      localVerificationData: 'local',
      serverVerificationData: receipt,
      source: 'test',
    ),
    transactionDate: '1767225600000',
    status: status,
  )..pendingCompletePurchase = pendingComplete;
  details.error = error;
  return details;
}

void main() {
  group('구매 성공 → 검증 요청 본문', () {
    test('iOS 구매는 platform 이 ios 이고 네 칸이 모두 채워진다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.verify);
      expect(verdict.body, {
        'platform': 'ios',
        'product_id': 'onpar.sheets.10',
        'transaction_id': 'txn-1001',
        'receipt': 'receipt-blob',
      });
    });

    test('Android 구매는 platform 이 android 다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased, productID: 'onpar.sheets.30'),
        platform: 'android',
      );

      expect(verdict.action, PurchaseAction.verify);
      expect(verdict.body!['platform'], 'android');
      expect(verdict.body!['product_id'], 'onpar.sheets.30');
    });

    test('검증 전에는 거래를 닫지 않는다', () {
      // 먼저 닫으면 검증이 실패했을 때 스토어가 다시 보내주지 않는다 = 돈만 받고 지급 없음.
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased),
        platform: 'ios',
      );

      expect(verdict.complete, isFalse);
    });

    test('복원된 구매도 똑같이 검증한다', () {
      // iOS 심사의 "구매 복원" 은 이 갈래로 들어온다. 여기서 빠지면 복원이 아무 일도 안 한다.
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.restored),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.verify);
      expect(verdict.body!['transaction_id'], 'txn-1001');
    });

    test('purchaseID 가 비면 구매 토큰을 거래 식별자로 쓴다', () {
      // 안드로이드 프로모션·테스트 구매는 orderId 가 비어서 온다.
      // 여기서 빈 문자열을 보내면 서버의 unique(platform, transaction_id) 가
      // 서로 다른 구매를 같은 건으로 묶어 두 번째 구매를 통째로 삼킨다.
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased, purchaseID: '', receipt: 'token-xyz'),
        platform: 'android',
      );

      expect(verdict.body!['transaction_id'], 'token-xyz');
    });

    test('purchaseID 가 null 이어도 토큰으로 대신한다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased, purchaseID: null, receipt: 'token-abc'),
        platform: 'android',
      );

      expect(verdict.body!['transaction_id'], 'token-abc');
      expect(transactionIdOf(
        _purchase(status: PurchaseStatus.purchased, purchaseID: null, receipt: 'token-abc'),
        platform: 'android',
      ), 'token-abc');
    });

    test('영수증이 비면 검증을 부르지 않고, 거래도 닫지 않는다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased, receipt: ''),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.failed);
      expect(verdict.body, isNull);
      // 닫지 않아야 스토어가 다시 보내준다.
      expect(verdict.complete, isFalse);
      expect(verdict.error, isNotNull);
    });
  });

  group('취소와 실패', () {
    test('사용자 취소는 오류가 아니라 cancelled 다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.canceled),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.cancelled);
      expect(verdict.error!.kind, AppErrorKind.cancelled);
      expect(verdict.error!.isCancelled, isTrue);
      // 취소는 여기서 끝난 거래다 — 닫지 않으면 iOS 가 계속 다시 보낸다.
      expect(verdict.complete, isTrue);
      expect(verdict.body, isNull);
    });

    test('취소인데 닫을 게 없으면 완료 호출도 하지 않는다', () {
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.canceled, pendingComplete: false),
        platform: 'android',
      );

      expect(verdict.action, PurchaseAction.cancelled);
      expect(verdict.complete, isFalse);
    });

    test('스토어 오류는 failed 이고 서버로 아무것도 보내지 않는다', () {
      final verdict = readPurchase(
        _purchase(
          status: PurchaseStatus.error,
          error: IAPError(source: 'app_store', code: 'storekit_generic', message: 'boom'),
        ),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.failed);
      expect(verdict.body, isNull);
      expect(verdict.complete, isTrue);
      // 서버 원문("boom")이 사용자 문구로 새지 않는다.
      expect(verdict.error!.message.contains('boom'), isFalse);
      expect(verdict.error!.message.isNotEmpty, isTrue);
    });

    test('대기 중인 결제는 기다린다 — 실패로 취급하지 않는다', () {
      // 가족 승인 대기가 여기로 온다. 실패로 그리면 사용자가 다시 결제한다.
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.pending),
        platform: 'ios',
      );

      expect(verdict.action, PurchaseAction.wait);
      expect(verdict.body, isNull);
      expect(verdict.complete, isFalse);
      expect(verdict.error, isNull);
    });
  });

  group('본문 모양', () {
    test('요청 본문에는 정확히 네 칸만 들어간다', () {
      // 서버 계약이다. 여기에 사용자 식별자나 가격을 얹기 시작하면
      // 앱이 주장하는 값을 서버가 믿게 되는 길이 열린다.
      final verdict = readPurchase(
        _purchase(status: PurchaseStatus.purchased),
        platform: 'ios',
      );

      expect(
        verdict.body!.keys.toSet(),
        {'platform', 'product_id', 'transaction_id', 'receipt'},
      );
    });
  });
}
