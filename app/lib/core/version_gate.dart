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
    final store = json['store_url'] as String?;

    if (current > 0 && minBuild > current) {
      return AppGate(decision: GateDecision.forceUpdate, message: json['message'] as String?, storeUrl: store);
    }
    if (current > 0 && latestBuild > current) {
      return AppGate(decision: GateDecision.optionalUpdate, message: json['message'] as String?, storeUrl: store);
    }
    return pass;
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
