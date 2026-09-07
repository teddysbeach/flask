import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/app_error.dart';
import '../../core/logger.dart';
import '../../data/profile_repository.dart';
import '../../data/storage_repository.dart';
import '../../data/supabase.dart';
import '../../domain/models.dart';
import '../../ui/states/app_state_views.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';

/// 프로필. 닉네임과 사진.
///
/// 닉네임 중복은 서버가 보지 않는다(같은 이름을 여럿이 써도 되는 제품이다).
/// 그래서 앱도 "이미 쓰는 이름이에요" 같은 말을 하지 않는다 —
/// 확인하지 않은 것을 확인한 척하면 사용자는 없는 문제를 고치려 든다.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// 닉네임 규칙. 화면과 테스트가 같이 쓴다.
class NicknameRule {
  const NicknameRule._();

  static const min = 2;
  static const max = 20;

  /// 통과하면 null, 아니면 사용자에게 보여줄 문구.
  static String? validate(String raw) {
    final name = raw.trim();
    if (name.isEmpty) return '닉네임을 적어 주세요.';
    // 길이는 룬으로 센다 — 이모지 하나를 2자로 세면 사용자가 보는 길이와 어긋난다.
    final length = name.runes.length;
    if (length < min) return '$min자 이상으로 적어 주세요.';
    if (length > max) return '$max자까지 쓸 수 있어요.';
    if (RegExp(r'\s{2,}').hasMatch(name)) return '띄어쓰기는 한 칸씩만 넣어 주세요.';
    if (name.contains('\n')) return '줄바꿈은 넣을 수 없어요.';
    return null;
  }
}

/// 프로필 사진 규칙. 스토리지에 올리기 전에 앱이 먼저 막는다 —
/// 서버까지 갔다가 거절당하면 사용자는 5MB 를 헛되이 업로드한 뒤에야 알게 된다.
class AvatarRule {
  const AvatarRule._();

  /// 버킷(`avatars`)이 2MB 에서 끊는다. 앱이 더 크게 잡으면 사용자는 다 올린 뒤에 거절당한다.
  static const maxBytes = 2 * 1024 * 1024;
  static const allowedExtensions = {'jpg', 'jpeg', 'png'};

  static String extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String? validate({required String path, required int bytes}) {
    final ext = extensionOf(path);
    if (!allowedExtensions.contains(ext)) {
      return 'JPG 나 PNG 사진만 올릴 수 있어요. 다른 사진으로 골라 주세요.';
    }
    if (bytes > maxBytes) {
      return '사진이 너무 커요(2MB까지). 다른 사진을 골라 주세요.';
    }
    return null;
  }
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _picker = ImagePicker();

  String? _initialName;
  bool _hydrated = false;

  /// 방금 고른 사진의 로컬 파일. 서명 URL 을 받아오기 전에도 바뀐 얼굴을 바로 보여준다.
  String? _localPreview;

  bool _saving = false;
  bool _uploading = false;
  double _progress = 0;
  String? _uploadError;
  XFile? _lastPick;

  @override
  void initState() {
    super.initState();
    // 프로바이더에 이미 값이 있으면 첫 프레임 전에 채운다. build 안에서 컨트롤러를 건드리면
    // 그리는 도중에 알림이 나가서, 사용자가 타이핑하던 글자가 되감기는 버그가 된다.
    _hydrate(ref.read(profileProvider).valueOrNull);
  }

  /// 서버 값으로 입력칸을 딱 한 번 채운다. 두 번 채우면 사용자가 고치던 것을 덮어쓴다.
  void _hydrate(Profile? me) {
    if (_hydrated || me == null) return;
    _hydrated = true;
    _initialName = me.displayName ?? '';
    _name.text = _initialName!;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// 사진은 고르는 즉시 올라가고 저장까지 끝난다(반쯤 저장된 프로필을 만들지 않으려는 것).
  /// 그래서 "저장 안 한 변경" 은 닉네임뿐이다 — 사진까지 여기 넣으면
  /// 이미 저장된 것을 두고 "버릴까요?" 를 묻게 된다.
  bool get _dirty => _initialName != null && _name.text.trim() != _initialName;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    ref.listen(profileProvider, (_, next) => _hydrate(next.valueOrNull));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '바꾼 내용을 버릴까요?',
          message: '저장하지 않은 닉네임은 사라져요. (사진은 이미 저장됐어요.)',
          confirmLabel: '버리기',
          cancelLabel: '계속 쓰기',
        );
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: SafeArea(
          child: dsAsync(profile,
            loading: () => const LoadingView(label: '프로필을 불러오는 중'),
            error: (e, st) => ErrorView(
              error: AppError.from(e, st),
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: _form,
          ),
        ),
      ),
    );
  }

  Widget _form(Profile me) {
    final p = DsTheme.of(context);
    final nameError = NicknameRule.validate(_name.text);

    return ListView(
      padding: const EdgeInsets.all(DsSpace.s4),
      children: [
        Center(
          child: Column(
            children: [
              _Avatar(
                localPath: _localPreview,
                // 서명 URL 은 만료되므로 DB 가 아니라 화면이 뜰 때마다 새로 받는다.
                remoteUrl: ref.watch(avatarUrlProvider).valueOrNull,
                fallback: (me.displayName ?? '').trim(),
                uploading: _uploading,
                progress: _progress,
              ),
              const SizedBox(height: DsSpace.s3),
              TextButton(
                onPressed: _uploading ? null : () => unawaited(_openPicker()),
                child: const Text('사진 바꾸기'),
              ),
            ],
          ),
        ),
        if (_uploadError != null) ...[
          const SizedBox(height: DsSpace.s2),
          NoticeBox(tone: NoticeTone.danger, text: _uploadError!),
          const SizedBox(height: DsSpace.s2),
          OutlinedButton(
            onPressed: _uploading || _lastPick == null
                ? null
                : () => unawaited(_upload(_lastPick!)),
            child: const Text('사진 올리기 다시 시도'),
          ),
        ],
        const SizedBox(height: DsSpace.s6),
        TextField(
          controller: _name,
          maxLength: NicknameRule.max,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '닉네임',
            hintText: '학습지에 표시될 이름',
            errorText: _name.text.isEmpty ? null : nameError,
            counterText: '',
          ),
        ),
        const SizedBox(height: DsSpace.s2),
        Text(
          '${NicknameRule.min}~${NicknameRule.max}자. 같은 닉네임을 다른 분이 쓰고 있어도 괜찮아요.',
          style: dsTextStyle(DsType.caption, p.textTertiary),
        ),
        const SizedBox(height: DsSpace.s8),
        OnceButton(
          enabled: !_uploading && nameError == null && _dirty,
          onPressed: _save,
          child: Text(_saving ? '저장 중' : '저장'),
        ),
      ],
    );
  }

  Future<void> _openPicker() async {
    final source = await AppFeedback.sheet<_PickAction>(
      context,
      builder: (ctx) {
        final p = DsTheme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s6, DsSpace.s4, DsSpace.s2),
                child: Text('프로필 사진', style: dsTextStyle(DsType.h3, p.textPrimary)),
              ),
              SettingsTile(
                label: '카메라로 찍기',
                icon: DsIcons.secObserve,
                showChevron: false,
                onTap: () => Navigator.of(ctx).pop(_PickAction.camera),
              ),
              SettingsTile(
                label: '앨범에서 고르기',
                icon: DsIcons.library,
                showChevron: false,
                onTap: () => Navigator.of(ctx).pop(_PickAction.gallery),
              ),
              SettingsTile(
                label: '기본 이미지로 되돌리기',
                icon: DsIcons.undo,
                showChevron: false,
                onTap: () => Navigator.of(ctx).pop(_PickAction.reset),
              ),
              const SizedBox(height: DsSpace.s4),
            ],
          ),
        );
      },
    );
    if (source == null) return;

    if (source == _PickAction.reset) {
      await _resetAvatar();
      return;
    }

    await _pick(source == _PickAction.camera ? ImageSource.camera : ImageSource.gallery);
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        // 압축은 여기서 한다. 원본 4000px 사진을 그대로 올리면 통신비와 저장비가 같이 오른다.
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
        requestFullMetadata: false,
      );
      // 사용자가 앨범을 닫은 것은 실패가 아니다.
      if (file == null) return;

      final bytes = await file.length();
      final problem = AvatarRule.validate(path: file.path, bytes: bytes);
      if (problem != null) {
        if (!mounted) return;
        setState(() => _uploadError = problem);
        return;
      }
      await _upload(file);
    } on PlatformException catch (e) {
      if (!mounted) return;
      if (_isPermissionDenied(e.code)) {
        await _explainPermission(source);
        return;
      }
      AppLogger.error('image pick failed', error: e);
      setState(() => _uploadError = '사진을 불러오지 못했어요. 다시 시도해 주세요.');
    } catch (e, st) {
      AppLogger.error('image pick failed', error: e, stack: st);
      if (!mounted) return;
      setState(() => _uploadError = '사진을 불러오지 못했어요. 다시 시도해 주세요.');
    }
  }

  /// image_picker 가 권한 거부에 쓰는 코드. 이건 "실패" 가 아니라 "설정으로 보내야 할 상황" 이다.
  static const _permissionDeniedCodes = {'camera_access_denied', 'photo_access_denied'};

  static bool _isPermissionDenied(String code) => _permissionDeniedCodes.contains(code);

  /// 권한이 막혔을 때. 앱 안에서는 더 물어볼 수 없다 — iOS 는 두 번째 요청을 띄우지 않는다.
  /// 그래서 "설정으로 가기" 를 직접 열어 준다. 여기서 그냥 실패라고만 하면 사용자는 길을 잃는다.
  Future<void> _explainPermission(ImageSource source) async {
    final what = source == ImageSource.camera ? '카메라' : '사진';
    final go = await AppFeedback.confirm(
      context,
      title: '$what 접근이 꺼져 있어요',
      message: '설정에서 ONPAR 의 $what 접근을 켜면 프로필 사진을 바꿀 수 있어요. '
          '지금 설정을 열어 드릴까요?',
      confirmLabel: '설정 열기',
      cancelLabel: '나중에',
    );
    if (!go) return;
    await openAppSettings();
  }

  /// 올린 뒤에 DB 를 고친다. 순서를 뒤집으면 `avatar_path` 는 있는데 파일이 없어서
  /// 프로필 사진이 영영 안 뜨는 상태가 남는다.
  Future<void> _upload(XFile file) async {
    final userId = ref.read(currentUserProvider)?.id;
    if (userId == null) {
      setState(() => _uploadError = AppError.of(AppErrorKind.unauthorized).message);
      return;
    }
    final previous = ref.read(profileProvider).valueOrNull?.avatarPath;

    setState(() {
      _lastPick = file;
      _uploading = true;
      _progress = 0;
      _uploadError = null;
    });

    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      // 읽기는 끝났고 이제 올린다. 진행률은 두 단계뿐이다 —
      // storage 클라이언트가 바이트 진행률을 주지 않으므로, 있지도 않은 숫자를 지어내지 않는다.
      setState(() => _progress = 0.4);

      final ext = AvatarRule.extensionOf(file.path);
      // 같은 이름으로 덮어쓰면 캐시가 옛 사진을 계속 보여준다. 그래서 이름을 새로 만들고,
      // DB 까지 성공한 뒤에 옛 파일을 지운다 — 안 지우면 사진을 바꿀 때마다 쓰레기가 쌓인다.
      final path = StoragePaths.avatar(
        userId: userId,
        extension: ext,
        stamp: DateTime.now().millisecondsSinceEpoch,
      );

      await ref.read(storageRepositoryProvider).putAvatar(
            path,
            bytes,
            contentType: StoragePaths.avatarContentType(ext),
          );
      if (mounted) setState(() => _progress = 0.8);

      await ref.read(profileRepositoryProvider).setAvatarPath(path);

      if (previous != null && previous.isNotEmpty && previous != path) {
        // 여기서 실패해도 사용자에게는 아무 일도 아니다(새 사진은 이미 저장됐다). 쓰레기 파일만 남는다.
        try {
          await ref.read(storageRepositoryProvider).removeAvatar(previous);
        } catch (e, st) {
          AppLogger.error('옛 프로필 사진 삭제 실패', error: e, stack: st);
        }
      }

      ref.invalidate(profileProvider);
      if (!mounted) return;
      setState(() {
        _localPreview = file.path;
        _uploading = false;
        _progress = 1;
        _lastPick = null;
      });
      AppFeedback.toast(context, '프로필 사진을 바꿨어요.');
    } catch (e, st) {
      final err = AppError.from(e, st);
      AppLogger.error('avatar upload failed', error: err, stack: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        // 실패 원인이 용량·형식이면 다시 시도해도 같은 결과다. 그때는 그 문구를 그대로 보여준다.
        _uploadError = err.kind == AppErrorKind.validation
            ? err.message
            : '사진을 올리지 못했어요. 잠시 뒤에 다시 시도해 주세요.';
      });
    }
  }

  /// 기본 이미지로 되돌리기: 파일을 지우고 `avatar_path` 를 비운다.
  /// DB 를 먼저 비운다 — 파일부터 지우면 실패했을 때 "경로는 있는데 사진이 없는" 상태가 남는다.
  Future<void> _resetAvatar() async {
    final previous = ref.read(profileProvider).valueOrNull?.avatarPath;
    setState(() {
      _uploadError = null;
      _lastPick = null;
    });
    if (previous == null || previous.isEmpty) {
      setState(() => _localPreview = null);
      return;
    }

    setState(() => _uploading = true);
    try {
      await ref.read(profileRepositoryProvider).setAvatarPath(null);
      try {
        await ref.read(storageRepositoryProvider).removeAvatar(previous);
      } catch (e, st) {
        AppLogger.error('프로필 사진 파일 삭제 실패', error: e, stack: st);
      }
      ref.invalidate(profileProvider);
      if (!mounted) return;
      setState(() {
        _localPreview = null;
        _uploading = false;
      });
      AppFeedback.toast(context, '기본 이미지로 되돌렸어요.');
    } catch (e, st) {
      final err = AppError.from(e, st);
      AppLogger.error('avatar reset failed', error: err, stack: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = '기본 이미지로 되돌리지 못했어요. 잠시 뒤에 다시 시도해 주세요.';
      });
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (NicknameRule.validate(name) != null) return;
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).update(displayName: name);
      ref.invalidate(profileProvider);
      if (!mounted) return;
      setState(() => _initialName = name);
      AppFeedback.toast(context, '프로필을 저장했어요.');
      context.pop();
    } on AppError catch (e) {
      if (!mounted) return;
      AppFeedback.toast(context, e.message, danger: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

enum _PickAction { camera, gallery, reset }

/// 동그란 프로필 사진. 사진이 없으면 닉네임 첫 글자를 쓴다.
///
/// 방금 고른 로컬 파일이 있으면 그것을, 없으면 서명 URL 을 쓴다.
/// 올린 직후에 서명 URL 을 기다리면 얼굴이 잠깐 옛 사진으로 돌아갔다 온다.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.localPath,
    required this.remoteUrl,
    required this.fallback,
    required this.uploading,
    required this.progress,
  });

  final String? localPath;
  final String? remoteUrl;
  final String fallback;
  final bool uploading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final initial = fallback.isEmpty ? '나' : fallback.characters.first;
    final letter = Text(initial, style: dsTextStyle(DsType.h1, p.textTertiary));
    final local = localPath;
    final remote = remoteUrl;

    Widget face;
    if (local != null) {
      face = Image.file(
        File(local),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        // 파일이 지워졌거나 못 읽으면 기본 얼굴로 돌아간다 — 깨진 아이콘을 보이지 않는다.
        errorBuilder: (_, __, ___) => letter,
      );
    } else if (remote != null) {
      face = Image.network(
        remote,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        // 서명 URL 이 만료됐거나 네트워크가 끊겨도 프로필 화면은 멀쩡해야 한다.
        errorBuilder: (_, __, ___) => letter,
      );
    } else {
      face = letter;
    }

    return Semantics(
      label: uploading
          ? '프로필 사진 올리는 중 ${(progress * 100).round()} 퍼센트'
          : local == null && remote == null
              ? '기본 프로필 사진'
              : '프로필 사진',
      liveRegion: uploading,
      child: SizedBox(
        width: 104,
        height: 104,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipOval(
              child: Container(
                width: 96,
                height: 96,
                color: p.surfaceSunken,
                alignment: Alignment.center,
                child: face,
              ),
            ),
            if (uploading)
              SizedBox(
                width: 104,
                height: 104,
                child: CircularProgressIndicator(
                  value: progress == 0 ? null : progress,
                  strokeWidth: 3,
                  color: p.brandText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
