/// 서버가 주는 것을 앱이 쓰는 모양으로. 화면은 이 타입만 알고 DB 컬럼 이름은 모른다.
library;

class Profile {
  const Profile({
    required this.id,
    this.displayName,
    this.avatarPath,
    required this.quotaTotal,
    required this.quotaUsed,
    required this.locale,
    required this.reviewHour,
    required this.timezone,
  });

  final String id;
  final String? displayName;

  /// 프로필 사진의 **Storage 경로**(`<user_id>/avatar_<stamp>.jpg`). URL 이 아니다.
  /// 버킷이 비공개라 볼 때마다 서명 URL 을 새로 받는다 — 서명 URL 은 만료되므로
  /// DB 에 넣으면 얼마 뒤부터 깨진 사진이 남는다.
  final String? avatarPath;
  final int quotaTotal;
  final int quotaUsed;
  final String locale;

  /// 복습 알림을 받을 로컬 시각(0~23).
  final int reviewHour;
  final String timezone;

  int get quotaRemaining => (quotaTotal - quotaUsed).clamp(0, 1 << 30);
  bool get canCreate => quotaRemaining > 0;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        displayName: m['display_name'] as String?,
        avatarPath: m['avatar_path'] as String?,
        quotaTotal: (m['quota_total'] as num?)?.toInt() ?? 0,
        quotaUsed: (m['quota_used'] as num?)?.toInt() ?? 0,
        locale: m['locale'] as String? ?? 'ko',
        reviewHour: (m['review_hour'] as num?)?.toInt() ?? 21,
        timezone: m['timezone'] as String? ?? 'Asia/Seoul',
      );

  /// `clearAvatar` 가 따로 있는 이유: null 은 "안 바꿈" 이라 "사진을 지웠다" 를 표현할 수 없다.
  Profile copyWith({
    String? displayName,
    int? reviewHour,
    String? timezone,
    String? avatarPath,
    bool clearAvatar = false,
  }) => Profile(
        id: id,
        displayName: displayName ?? this.displayName,
        avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
        quotaTotal: quotaTotal,
        quotaUsed: quotaUsed,
        locale: locale,
        reviewHour: reviewHour ?? this.reviewHour,
        timezone: timezone ?? this.timezone,
      );
}

enum WorksheetStatus { queued, generating, ready, failed }

WorksheetStatus _status(String? s) => switch (s) {
      'ready' => WorksheetStatus.ready,
      'generating' => WorksheetStatus.generating,
      'failed' => WorksheetStatus.failed,
      _ => WorksheetStatus.queued,
    };

/// 생성이 지금 밟고 있는 단계. 서버(`worksheets.stage`)가 정하고 앱은 읽기만 한다.
///
/// 예전에는 이 값이 없어서 진행 화면이 **경과 시간만 보고 단계를 지어냈다.**
/// 18초가 지나면 "쓰고 있어요", 70초가 지나면 "검사하고 있어요" — 서버가 죽은 뒤에도
/// 화면은 계속 그렇게 말했다. 13분째 "품질을 검사하고 있어요" 를 본 사람이 잃는 것은
/// 시간이 아니라 다음에 이 앱이 하는 말을 믿을 이유다.
enum GenerationStage {
  plan, draft, critic, revise, render, save;

  static GenerationStage? parse(String? v) => switch (v) {
        'plan' => GenerationStage.plan,
        'draft' => GenerationStage.draft,
        'critic' => GenerationStage.critic,
        'revise' => GenerationStage.revise,
        'render' => GenerationStage.render,
        'save' => GenerationStage.save,
        _ => null,
      };
}

class WorksheetSummary {
  const WorksheetSummary({
    required this.id,
    required this.topic,
    required this.status,
    required this.createdAt,
    this.title,
    this.readyAt,
    this.errorCode,
    this.htmlPath,
    this.stage,
    this.stageAt,
  });

  final String id;
  final String topic;
  final String? title;
  final WorksheetStatus status;
  final DateTime createdAt;
  final DateTime? readyAt;
  final String? errorCode;
  final String? htmlPath;

  /// 서버가 말한 단계. null 이면 **아직 모른다** 는 뜻이고, 그러면 모른다고 말한다.
  final GenerationStage? stage;
  final DateTime? stageAt;

  String get displayTitle => title ?? topic;
  bool get isTerminal => status == WorksheetStatus.ready || status == WorksheetStatus.failed;

  /// 주문을 넣은 뒤 지난 시간. 화면이 세는 초가 아니라 **서버가 적은 시각** 기준이다 —
  /// 앱을 껐다 켜도, 다른 기기에서 봐도 같은 값이 나와야 한다.
  Duration age(DateTime now) => now.difference(createdAt);

  /// 같은 단계에 머문 시간. 모르면 null 이다.
  Duration? stuckFor(DateTime now) =>
      stageAt == null ? null : now.difference(stageAt!);

  /// 보통 걸리는 시간(40~120초)을 넘겼는가. 넘겼다고 실패는 아니지만,
  /// 넘겼는데도 "정상입니다" 라고 말하면 그게 거짓말이다.
  bool isSlow(DateTime now) => age(now) > const Duration(minutes: 3);

  /// 실패 코드를 사람 말로. 사용자는 `draft_quality_rejected` 를 읽을 이유가 없다.
  /// 어느 경우든 쿼터는 환불됐다는 사실을 같이 말한다 — 그게 사용자가 가장 궁금한 것이다.
  String get failureMessage => switch (errorCode) {
        'llm_refused' => '이 주제로는 학습지를 만들지 못했어요. 표현을 바꿔서 다시 시도해 주세요. 사용한 장수는 돌려드렸어요.',
        'draft_quality_rejected' =>
          '품질 기준을 못 넘어서 내보내지 않았어요. 덜 만들어진 학습지를 드리지 않으려는 거예요. 사용한 장수는 돌려드렸어요.',
        'render_failed' => '학습지를 그리는 중에 문제가 생겼어요. 사용한 장수는 돌려드렸어요.',
        // 서버가 중간에 끊겨 매달려 있던 건. 사용자는 아무 잘못이 없고, 장수는 이미 돌려받았다.
        'generation_stalled' =>
          '만드는 중에 연결이 끊겨서 마무리하지 못했어요. 사용한 장수는 돌려드렸으니 다시 시도해 주세요.',
        // 파이프라인이 스스로 벽시계 예산을 넘겨 끊은 경우.
        'generation_timeout' =>
          '만드는 데 너무 오래 걸려서 중간에 멈췄어요. 사용한 장수는 돌려드렸으니 다시 시도해 주세요.',
        'cost_cap_exceeded' =>
          '이 주제는 예상보다 훨씬 오래 걸려서 중간에 멈췄어요. 사용한 장수는 돌려드렸어요. 주제를 조금 좁혀서 다시 해 보시면 잘 나와요.',
        _ => '만드는 중에 문제가 생겼어요. 사용한 장수는 돌려드렸으니 다시 시도해 주세요.',
      };

  factory WorksheetSummary.fromMap(Map<String, dynamic> m) => WorksheetSummary(
        id: m['id'] as String,
        topic: m['topic'] as String? ?? '',
        title: m['title'] as String?,
        status: _status(m['status'] as String?),
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        readyAt: m['ready_at'] == null ? null : DateTime.parse(m['ready_at'] as String).toLocal(),
        errorCode: m['error_code'] as String?,
        htmlPath: m['html_path'] as String?,
        stage: GenerationStage.parse(m['stage'] as String?),
        stageAt: m['stage_at'] == null
            ? null
            : DateTime.parse(m['stage_at'] as String).toLocal(),
      );
}

class Product {
  const Product({required this.id, required this.sheets, required this.priceKrw});

  final String id;
  final int sheets;
  final int priceKrw;

  int get perSheet => (priceKrw / sheets).round();

  factory Product.fromMap(Map<String, dynamic> m) => Product(
        id: m['id'] as String,
        sheets: (m['sheets'] as num).toInt(),
        priceKrw: (m['price_krw'] as num).toInt(),
      );
}

class ReviewItem {
  const ReviewItem({
    required this.scheduleId,
    required this.quizItemId,
    required this.worksheetId,
    required this.question,
    required this.answer,
    required this.explanation,
    required this.dueAt,
    required this.repetition,
    this.choices,
    this.worksheetTitle,
  });

  final String scheduleId;
  final String quizItemId;
  final String worksheetId;
  final String question;
  final String answer;
  final String explanation;
  final DateTime dueAt;
  final int repetition;
  final List<String>? choices;
  final String? worksheetTitle;

  bool get isDue => !dueAt.isAfter(DateTime.now());
}

/// 약관 동의 이력. 무엇에 언제 동의했는지 남겨야 나중에 증명할 수 있다.
class ConsentRecord {
  const ConsentRecord({
    required this.terms,
    required this.privacy,
    required this.marketing,
    required this.agreedAt,
    required this.version,
  });

  final bool terms;
  final bool privacy;
  final bool marketing;
  final DateTime agreedAt;

  /// 약관 버전. 내용이 바뀌면 다시 받아야 한다.
  final String version;

  /// 지금 받고 있는 약관 버전. **약관 본문을 고치면 이 값을 올린다.**
  ///
  /// 화면이 아니라 여기에 둔다 — 동의 판정(라우터)과 동의 기록(동의 화면)이
  /// 서로 다른 상수를 보면, 올린 쪽만 바뀌고 판정은 옛 버전을 계속 통과시킨다.
  static const currentVersion = '1';

  bool get requiredAccepted => terms && privacy;

  /// 지금 약관으로 동의를 받았는가. 약관이 바뀌었으면 다시 받아야 한다 —
  /// 바뀐 약관을 안 보여주고 계속 쓰게 하면 그 동의는 법적으로도 의미가 없다.
  bool get isCurrent => requiredAccepted && version == currentVersion;

  Map<String, Object?> toJson() => {
        'terms': terms,
        'privacy': privacy,
        'marketing': marketing,
        'agreed_at': agreedAt.toIso8601String(),
        'version': version,
      };

  factory ConsentRecord.fromJson(Map<String, Object?> j) => ConsentRecord(
        terms: j['terms'] == true,
        privacy: j['privacy'] == true,
        marketing: j['marketing'] == true,
        agreedAt: DateTime.tryParse('${j['agreed_at']}') ?? DateTime.now(),
        version: '${j['version'] ?? '1'}',
      );
}
