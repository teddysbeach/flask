import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/connectivity.dart';
import '../../core/env.dart';
import '../../core/logger.dart';
import '../../ui/widgets/feedback.dart';
import '../settings/settings_tile.dart';

/// 어떤 문서인가.
enum LegalDoc {
  terms('이용약관', Env.termsUrl),
  privacy('개인정보처리방침', Env.privacyUrl);

  const LegalDoc(this.title, this.url);
  final String title;
  final String url;
}

/// 약관·방침 화면.
///
/// 원문은 웹에 있다 — 내용이 바뀔 때 앱 심사를 기다릴 수 없기 때문이다.
/// 그런데 웹만 믿으면 비행기 안에서, 지하철에서, 우리 서버가 죽었을 때 아무것도 안 보인다.
/// **약관은 못 보여줘도 되는 화면이 아니다.** 그래서 요약을 앱 안에 함께 둔다.
class LegalDocumentScreen extends ConsumerStatefulWidget {
  const LegalDocumentScreen({super.key, required this.doc});

  final LegalDoc doc;

  @override
  ConsumerState<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends ConsumerState<LegalDocumentScreen> {
  bool _failed = false;
  bool _loading = true;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final offline = ref.watch(netStatusProvider).valueOrNull == NetStatus.offline;
    final showSummary = offline || _failed;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.doc.title),
        actions: [
          IconButton(
            onPressed: () => unawaited(_openExternally()),
            tooltip: '브라우저로 열기',
            icon: DsIcon(
              DsIcons.zoomIn,
              size: 20,
              color: DsTheme.of(context).textSecondary,
            ),
          ),
        ],
      ),
      body: SafeArea(
        // 전문을 못 불러와 요약으로 떨어질 때. 갑자기 다른 글이 떠 있으면
        // 사용자는 자기가 뭘 잘못 눌렀다고 생각한다.
        child: DsSwitcher(
          child: KeyedSubtree(
            key: ValueKey(showSummary),
            child: showSummary ? _summary(offline) : _web(),
          ),
        ),
      ),
    );
  }

  Widget _web() {
    final p = DsTheme.of(context);
    return Stack(
      children: [
        InAppWebView(
          // 재시도할 때 위젯을 통째로 새로 만든다. reload 만으로는 실패 상태가 남는 기기가 있다.
          key: ValueKey('${widget.doc.name}-$_attempt'),
          initialUrlRequest: URLRequest(url: WebUri(widget.doc.url)),
          initialSettings: InAppWebViewSettings(
            // 약관 페이지에서 자바스크립트로 다른 곳에 갈 이유가 없다.
            javaScriptCanOpenWindowsAutomatically: false,
            supportZoom: true,
            transparentBackground: true,
          ),
          onLoadStop: (_, __) {
            if (mounted) setState(() => _loading = false);
          },
          onReceivedError: (_, __, error) {
            AppLogger.error('legal page load failed: ${error.type}');
            if (mounted) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
          },
          onReceivedHttpError: (_, __, response) {
            if ((response.statusCode ?? 0) >= 400 && mounted) {
              setState(() {
                _failed = true;
                _loading = false;
              });
            }
          },
        ),
        if (_loading)
          Positioned.fill(
            child: ColoredBox(
              color: p.surfaceBase,
              child: Semantics(
                liveRegion: true,
                label: '${widget.doc.title}을 불러오는 중',
                child: Center(child: CircularProgressIndicator(color: p.brandText)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _summary(bool offline) {
    final p = DsTheme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
      children: [
        NoticeBox(
          tone: NoticeTone.warning,
          title: offline ? '지금은 인터넷이 끊겨 있어요' : '전문을 불러오지 못했어요',
          text: '아래는 앱에 넣어 둔 요약이에요. 법적으로 효력을 갖는 것은 전문이라, '
              '연결되면 꼭 전문을 확인해 주세요.',
        ),
        const SizedBox(height: DsSpace.s4),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _retry,
                child: const Text('다시 시도'),
              ),
            ),
            const SizedBox(width: DsSpace.s2),
            Expanded(
              child: OutlinedButton(
                onPressed: () => unawaited(_openExternally()),
                child: const Text('브라우저로 열기'),
              ),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.s6),
        Text('${widget.doc.title} 요약', style: dsTextStyle(DsType.h2, p.textPrimary)),
        const SizedBox(height: DsSpace.s4),
        for (final section in legalSummary(widget.doc)) ...[
          Text(section.title, style: dsTextStyle(DsType.h3, p.textPrimary)),
          const SizedBox(height: DsSpace.s2),
          Text(section.body, style: dsTextStyle(DsType.body, p.textSecondary)),
          const SizedBox(height: DsSpace.s6),
        ],
        Text(
          '전문 주소: ${widget.doc.url}',
          style: dsTextStyle(DsType.caption, p.textTertiary),
        ),
      ],
    );
  }

  void _retry() {
    setState(() {
      _failed = false;
      _loading = true;
      _attempt++;
    });
  }

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.doc.url);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok || !mounted) return;
    } catch (e, st) {
      AppLogger.error('legal url launch failed', error: e, stack: st);
      if (!mounted) return;
    }
    AppFeedback.toast(context, '브라우저를 열지 못했어요. 요약을 대신 봐 주세요.', danger: true);
    setState(() => _failed = true);
  }
}

class LegalSection {
  const LegalSection(this.title, this.body);
  final String title;
  final String body;
}

/// 오프라인 요약. 전문을 대신하지 않지만, **아무것도 안 보여주는 것보다 언제나 낫다.**
/// 내용이 바뀌면 웹 전문과 함께 여기도 고친다.
List<LegalSection> legalSummary(LegalDoc doc) => switch (doc) {
      LegalDoc.terms => const [
          LegalSection(
            '무엇을 제공하나요',
            'ONPAR 은 배우고 싶은 개념을 넣으면 6단계 학습지를 만들어 드리고, 그 위에 필기하고, '
                '망각곡선에 맞춰 복습하도록 도와드리는 앱이에요.',
          ),
          LegalSection(
            '학습지를 만드는 권리(장수)',
            '가입하면 2장을 드려요. 더 필요하면 앱 안에서 구매할 수 있어요. '
                '장수는 새 학습지를 만들 때만 쓰여요. 이미 만든 학습지를 열고, 필기하고, '
                '복습 알림을 받는 것은 언제나 무료예요.\n\n'
                '학습지를 만들기 시작할 때 한 장이 빠지고, 만들다 실패하면 그 자리에서 돌려드려요.',
          ),
          LegalSection(
            '결제와 환불',
            '결제는 애플 App Store 와 구글 Play 를 통해 이뤄져요. 결제하면 장수가 바로 들어오므로 '
                '전자상거래법상 "용역 제공이 개시된" 경우에 해당해요. 그래도 아직 쓰지 않은 장수는 '
                '환불받을 수 있어요. 환불 신청은 결제하신 스토어에서 해요.\n\n'
                '환불이 처리되면 남은 장수에서 그만큼 빠져요. 이미 쓴 장수는 회수하지 않아요.',
          ),
          LegalSection(
            '만드신 것은 누구 것인가요',
            '학습지 위에 쓰신 필기와 응답은 사용자의 것이에요. 저희는 서비스를 제공하려고 보관할 뿐이고, '
                '탈퇴하시면 지워요.',
          ),
          LegalSection(
            '하지 말아 주세요',
            '다른 사람의 계정을 쓰거나, 앱을 뜯어 고쳐 장수를 늘리거나, 서비스를 자동화 도구로 '
                '무리하게 두드리는 일은 하지 말아 주세요. 그런 경우 이용을 제한할 수 있어요.',
          ),
          LegalSection(
            '서비스가 멈출 수 있어요',
            '점검이나 사고로 잠시 멈출 수 있어요. 미리 알 수 있는 점검은 앱에서 안내해 드려요. '
                '저희 잘못으로 손해를 드렸다면 법이 정한 범위에서 책임을 져요.',
          ),
          LegalSection(
            '약관이 바뀌면',
            '중요한 내용이 바뀔 때는 앱에서 미리 알려드리고 다시 동의를 받아요.',
          ),
        ],
      LegalDoc.privacy => const [
          LegalSection(
            '무엇을 모으나요',
            '이메일 주소(또는 Apple·Google 로그인 식별자), 닉네임, 만드신 학습지와 필기, '
                '복습 기록, 결제 내역이에요. 앱이 잘 도는지 보려고 오류 기록도 남겨요.\n\n'
                '광고 식별자는 쓰지 않고, 연락처·위치·통화 기록은 가져가지 않아요.',
          ),
          LegalSection(
            '왜 모으나요',
            '계정을 알아보고, 학습지를 만들어 드리고, 복습 시간을 맞추고, 결제를 확인하려고요. '
                '그 밖의 목적으로는 쓰지 않아요.',
          ),
          LegalSection(
            '누구에게 주나요',
            '학습지를 만들 때 주제 문장이 생성 모델 제공자에게 전달돼요. 이때 이메일이나 계정 ID 같은 '
                '식별자는 함께 보내지 않아요.\n\n'
                '결제 확인은 애플·구글과 하고, 데이터 보관은 Supabase 를 써요. '
                '그 외에 개인정보를 파는 일은 없어요.',
          ),
          LegalSection(
            '얼마나 보관하나요',
            '계정이 살아 있는 동안 보관하고, 탈퇴하시면 학습지·필기·복습 기록·응답을 지워요.\n\n'
                '다만 구매 내역은 전자상거래법에 따라 5년 동안 보관해야 해요. 이때는 누구의 것인지 '
                '알 수 없게 바꿔서 남겨요.',
          ),
          LegalSection(
            '어떤 권리가 있나요',
            '열람·정정·삭제·처리 정지를 요구하실 수 있어요. 앱 안에서 프로필을 고치거나 '
                '탈퇴하실 수 있고, 그 밖의 요청은 고객센터로 보내주시면 처리해 드려요.',
          ),
          LegalSection(
            '기기 권한',
            '프로필 사진과 문의 스크린샷을 위해 카메라·사진 접근을 물어봐요. 거절하셔도 나머지 기능은 '
                '모두 쓸 수 있어요. 복습 알림을 받으시려면 알림 권한이 필요해요.',
          ),
          LegalSection(
            '어디로 문의하나요',
            '${Env.supportEmail} 으로 보내주시면 확인해 드려요.',
          ),
        ],
    };
