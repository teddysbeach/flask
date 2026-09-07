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

  static const maxBytes = 5 * 1024 * 1024;
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
      return '사진이 너무 커요(5MB까지). 다른 사진을 골라 주세요.';
    }
    return null;
  }
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _name = TextEditingController();
  final _picker = ImagePicker();

  String? _initialName;
  String? _avatarPath;
  bool _avatarCleared = false;

  bool _saving = false;
  bool _uploading = false;
  double _progress = 0;
  String? _uploadError;
  XFile? _lastPick;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty =>
      (_initialName != null && _name.text.trim() != _initialName) ||
      _avatarPath != null ||
      _avatarCleared;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_dirty) return;
        final leave = await AppFeedback.confirm(
          context,
          title: '바꾼 내용을 버릴까요?',
          message: '저장하지 않은 닉네임과 사진은 사라져요.',
          confirmLabel: '버리기',
          cancelLabel: '계속 쓰기',
        );
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: SafeArea(
          child: profile.when(
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
    _initialName ??= me.displayName ?? '';
    if (_name.text.isEmpty && _initialName!.isNotEmpty && !_dirty) {
      _name.text = _initialName!;
    }
    final nameError = NicknameRule.validate(_name.text);

    return ListView(
      padding: const EdgeInsets.all(DsSpace.s4),
      children: [
        Center(
          child: Column(
            children: [
              _Avatar(
                path: _avatarCleared ? null : _avatarPath,
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
      setState(() {
        _avatarPath = null;
        _lastPick = null;
        _uploadError = null;
        _avatarCleared = true;
      });
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

  Future<void> _upload(XFile file) async {
    setState(() {
      _lastPick = file;
      _uploading = true;
      _progress = 0;
      _uploadError = null;
    });

    try {
      // TODO(storage): Supabase Storage `avatars` 버킷에 올리고 public URL 을 profiles 에 쓴다.
      //   업로드 진행률은 그때 실제 바이트 진행률로 갈아끼운다. 지금은 화면 흐름만 완성해 둔다.
      //   올린 뒤에는 이전 파일을 지운다 — 안 지우면 사진을 바꿀 때마다 쓰레기가 쌓인다.
      for (var step = 1; step <= 5; step++) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!mounted) return;
        setState(() => _progress = step / 5);
      }
      if (!mounted) return;
      setState(() {
        _avatarPath = file.path;
        _avatarCleared = false;
        _uploading = false;
      });
      AppFeedback.toast(context, '프로필 사진을 바꿨어요.');
    } catch (e, st) {
      AppLogger.error('avatar upload failed', error: e, stack: st);
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _uploadError = '사진을 올리지 못했어요. 잠시 뒤에 다시 시도해 주세요.';
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
      setState(() {
        _initialName = name;
        _avatarPath = null;
        _avatarCleared = false;
      });
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
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.path,
    required this.fallback,
    required this.uploading,
    required this.progress,
  });

  final String? path;
  final String fallback;
  final bool uploading;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final initial = fallback.isEmpty ? '나' : fallback.characters.first;

    return Semantics(
      label: uploading
          ? '프로필 사진 올리는 중 ${(progress * 100).round()} 퍼센트'
          : path == null
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
                child: path == null
                    ? Text(initial, style: dsTextStyle(DsType.h1, p.textTertiary))
                    : Image.file(
                        File(path!),
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        // 파일이 지워졌거나 못 읽으면 기본 얼굴로 돌아간다 — 깨진 아이콘을 보이지 않는다.
                        errorBuilder: (_, __, ___) =>
                            Text(initial, style: dsTextStyle(DsType.h1, p.textTertiary)),
                      ),
              ),
            ),
            if (uploading)
              SizedBox(
                width: 104,
                height: 104,
                child: CircularProgressIndicator(
                  value: progress == 0 ? null : progress,
                  strokeWidth: 3,
                  color: p.brandPrimary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
