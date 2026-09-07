import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱을 켰을 때 "지금 들어가도 되는가" 를 정하는 관문.
///
/// 강제 업데이트와 점검 공지는 서버가 정한다. 앱에 박아두면 사고가 났을 때
/// 스토어 심사(며칠)를 기다려야 사용자를 막을 수 있다.
enum GateDecision { ok, optionalUpdate, forceUpdate, maintenance }

class AppGate {
  const AppGate({
    required this.decision,
    this.message,
    this.storeUrl,
    this.until,
  });

  final GateDecision decision;
  final String? message;
  final String? storeUrl;

  /// 점검 종료 예정 시각. 모르면 null — 모르면서 아는 척 하지 않는다.
  final DateTime? until;

  static const pass = AppGate(decision: GateDecision.ok);

  /// 서버 응답 → 판정. 서버가 이상한 값을 줘도 앱은 열려야 하므로 기본은 통과다.
  factory AppGate.fromJson(Map<String, Object?> json, String currentBuild) {
    final maintenance = json['maintenance'] == true;
    if (maintenance) {
      return AppGate(
        decision: GateDecision.maintenance,
        message: json['message'] as String?,
        until: DateTime.tryParse((json['until'] as String?) ?? ''),
      );
    }
    final minBuild = int.tryParse('${json['min_build'] ?? ''}') ?? 0;
    final latestBuild = int.tryParse('${json['latest_build'] ?? ''}') ?? 0;
    final current = int.tryParse(currentBuild) ?? 0;
    final store = safeStoreUrl(json['store_url']);

    if (current > 0 && minBuild > current) {
      return AppGate(decision: GateDecision.forceUpdate, message: json['message'] as String?, storeUrl: store);
    }
    if (current > 0 && latestBuild > current) {
      return AppGate(decision: GateDecision.optionalUpdate, message: json['message'] as String?, storeUrl: store);
    }
    return pass;
  }

  /// 서버가 준 스토어 주소를 거른다.
  ///
  /// 이 값은 앱이 `launchUrl` 로 **바깥에 그대로 넘기는** 유일한 서버 문자열이다.
  /// 거르지 않으면 설정 한 줄이 바뀌는 것만으로 앱이 아무 주소나 여는 도구가 된다.
  /// 스토어로 보내는 데 필요한 것은 셋뿐이라, 나머지는 전부 버린다 —
  /// 버리면 화면이 "스토어에서 ONPAR 를 찾아 주세요" 로 안내한다(막히지 않는다).
  static String? safeStoreUrl(Object? raw) {
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return null;
    const allowed = {'https', 'itms-apps', 'market'};
    if (!allowed.contains(uri.scheme.toLowerCase())) return null;
    // https 는 반드시 진짜 스토어여야 한다. 우리 안내문이 "스토어" 라고 말하기 때문이다.
    if (uri.scheme.toLowerCase() == 'https') {
      const hosts = {'apps.apple.com', 'itunes.apple.com', 'play.google.com'};
      if (!hosts.contains(uri.host.toLowerCase())) return null;
    }
    return uri.toString();
  }
}

class AppInfo {
  const AppInfo({required this.version, required this.build, required this.packageName});
  final String version;
  final String build;
  final String packageName;

  String get display => '$version ($build)';
}

final appInfoProvider = FutureProvider<AppInfo>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(version: info.version, build: info.buildNumber, packageName: info.packageName);
});
