import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// 권한 요청. 두 가지를 지킨다.
///
/// 1. **필요한 순간에만 묻는다.** 첫 실행에 몰아서 물으면 대부분 거절하고, 거절은 되돌리기 어렵다.
///    알림은 첫 학습지를 만든 뒤에, 사진은 프로필을 바꿀 때 묻는다.
/// 2. **영구 거절을 구분한다.** 영구 거절이면 다시 물어도 창이 안 뜬다 —
///    그때는 시스템 설정으로 보내야 한다. 이걸 구분 못 하면 사용자는 안 뜨는 버튼을 계속 누른다.
enum PermissionOutcome { granted, denied, permanentlyDenied, restricted }

extension PermissionOutcomeX on PermissionOutcome {
  bool get isGranted => this == PermissionOutcome.granted;

  /// 앱 안에서 해결할 수 없는 상태. 안내를 띄우고 설정으로 보내야 한다.
  bool get needsSettings =>
      this == PermissionOutcome.permanentlyDenied || this == PermissionOutcome.restricted;
}

class PermissionService {
  const PermissionService();

  Future<PermissionOutcome> notifications() => _ask(Permission.notification);

  /// 프로필 사진용. iOS 는 사진 접근이 제한 허용(limited)일 수 있는데 그건 우리에겐 충분하다.
  Future<PermissionOutcome> photos() => _ask(Permission.photos);
  Future<PermissionOutcome> camera() => _ask(Permission.camera);

  Future<PermissionOutcome> status(Permission p) async => _map(await p.status);

  Future<PermissionOutcome> _ask(Permission p) async {
    final current = await p.status;
    if (current.isGranted || current.isLimited) return PermissionOutcome.granted;
    if (current.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return _map(await p.request());
  }

  static PermissionOutcome _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermissionOutcome.granted;
    if (s.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    if (s.isRestricted) return PermissionOutcome.restricted;
    return PermissionOutcome.denied;
  }

  Future<bool> openSettings() => openAppSettings();
}

final permissionServiceProvider = Provider<PermissionService>((_) => const PermissionService());
