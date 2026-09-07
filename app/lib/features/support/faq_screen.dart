import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/routes.dart';

/// 자주 묻는 질문.
///
/// 답은 짧게 쓰되 **결론을 첫 줄에 둔다.** 사용자는 설명을 읽으러 온 게 아니라
/// 자기 상황이 괜찮은지 확인하러 온다. 특히 돈과 필기에 관한 질문이 그렇다.
class FaqScreen extends ConsumerWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = DsTheme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('자주 묻는 질문')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
          children: [
            for (final (i, item) in faqItems.indexed) ...[
              DsFadeSlide(delay: dsStaggerDelay(i), child: _FaqCard(item: item)),
              const SizedBox(height: DsSpace.s2),
            ],
            const SizedBox(height: DsSpace.s6),
            Text(
              '찾는 답이 없나요?',
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
            const SizedBox(height: DsSpace.s2),
            OutlinedButton(
              onPressed: () => context.push(Routes.contact),
              child: const Text('문의하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class FaqItem {
  const FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

/// ONPAR 을 쓰다 실제로 막히는 지점들.
const faqItems = <FaqItem>[
  FaqItem(
    question: '학습지가 안 만들어져요',
    answer: '학습지 한 장을 만드는 데 보통 1~2분이 걸려요. 그 사이에 앱을 꺼도 괜찮아요 — '
        '만들기는 저희 서버에서 계속되고, 다 되면 보관함에 나타나요.\n\n'
        '5분이 넘도록 "만드는 중" 이면 만들기가 실패했을 가능성이 커요. 이때 쓴 장수는 '
        '자동으로 돌려드려요. 보관함에서 다시 시도해 주시고, 그래도 안 되면 문의해 주세요.\n\n'
        '주제가 너무 넓거나(예: "과학") 너무 짧으면 만들다 멈추기도 해요. '
        '"광합성에서 빛에너지가 하는 일" 처럼 한 문장으로 좁혀 주시면 잘 나와요.',
  ),
  FaqItem(
    question: '장수는 언제 차감되나요',
    answer: '학습지를 만들기 시작할 때 한 장이 빠져요. 다 만들어졌을 때가 아니에요.\n\n'
        '대신 만들다 실패하면 그 자리에서 돌려드려요. 그래서 실패로 장수를 잃는 일은 없어요.\n\n'
        '이미 만든 학습지를 다시 열어 보거나, 필기하거나, 복습하는 것은 장수를 쓰지 않아요. '
        '몇 번을 열어도 무료예요.',
  ),
  FaqItem(
    question: '만들다 실패하면 환불되나요',
    answer: '네, 자동으로 돌려드려요. 따로 신청하지 않으셔도 돼요.\n\n'
        '만들기가 실패하는 경우는 세 가지예요. 주제로 학습지를 만들 수 없을 때, '
        '만들어진 내용이 저희 품질 기준을 못 넘었을 때, 그리고 저희 쪽에 문제가 생겼을 때예요. '
        '어느 쪽이든 쓴 장수는 그대로 돌아와요.\n\n'
        '덜 만들어진 학습지를 드리느니 다시 만드는 쪽이 낫다고 생각해서 이렇게 하고 있어요.',
  ),
  FaqItem(
    question: '필기가 사라졌어요',
    answer: '먼저 학습지를 다시 열어 봐 주세요. 필기는 쓰는 동안 자동으로 저장되지만, '
        '저장 직전에 앱이 꺼지면 마지막 몇 초가 빠질 수 있어요.\n\n'
        '오프라인에서 필기하신 거라면 기기 안에 남아 있어요. 인터넷에 연결되면 저절로 올라가요. '
        '연결한 뒤 학습지를 한 번 열어 주세요.\n\n'
        '그래도 안 보이면 문의해 주세요. 손으로 쓴 것은 사용자의 것이고, 저희가 끝까지 찾아볼게요.',
  ),
  FaqItem(
    question: '복습 알림이 안 와요',
    answer: '세 가지를 확인해 주세요.\n\n'
        '첫째, 기기 설정에서 ONPAR 의 알림이 켜져 있어야 해요. 설정 → 알림에서 볼 수 있어요.\n'
        '둘째, 앱 안의 설정 → 알림에서 받을 시간이 정해져 있어야 해요.\n'
        '셋째, 방해 금지 모드나 집중 모드가 켜져 있으면 그 시간에는 소리가 나지 않아요.\n\n'
        '복습은 정해진 간격(1일, 3일, 7일, 16일, 35일)으로 돌아와요. '
        '아직 그 날짜가 안 됐으면 알림이 오지 않는 게 정상이에요.',
  ),
  FaqItem(
    question: '아이패드가 아니어도 되나요',
    answer: '네, 아이폰과 안드로이드 폰에서도 다 돼요. 읽기·풀기·복습은 모두 똑같이 동작해요.\n\n'
        '다만 손가락으로 쓰는 필기는 펜만큼 정교하지 않아요. 필기를 많이 하실 거라면 '
        '애플펜슬을 쓰는 아이패드나, 펜을 지원하는 태블릿이 편해요.\n\n'
        '기기를 바꿔도 학습지와 필기는 계정을 따라가요. 다시 로그인하면 그대로 있어요.',
  ),
  FaqItem(
    question: '결제했는데 장수가 안 늘어요',
    answer: '먼저 설정 → 구매 내역에서 "구매 복원" 을 눌러 주세요. 결제는 됐는데 '
        '확인하는 중에 연결이 끊긴 경우, 이걸로 대부분 해결돼요.\n\n'
        '스토어에서 결제가 심사 대기(가족 승인 등)로 잡히면 승인된 뒤에 들어와요. '
        '이때는 조금 기다려 주셔야 해요.\n\n'
        '복원해도 그대로면 문의해 주세요. 결제하신 것은 반드시 반영해 드려요. '
        '스토어에서 받은 영수증 메일이 있으면 같이 보내주시면 더 빨라요.',
  ),
  FaqItem(
    question: '탈퇴하면 학습지는 어떻게 되나요',
    answer: '만든 학습지, 필기, 복습 일정, 문제 응답 기록이 모두 지워져요. 되돌릴 수 없어요.\n\n'
        '남아 있던 장수도 함께 사라지고, 환불되지 않아요. 탈퇴 전에 다 쓰시는 편이 좋아요.\n\n'
        '구매 내역은 전자상거래법이 정한 기간(5년) 동안 누구의 것인지 알 수 없게 바꿔서 보관해요. '
        '이건 법이 요구하는 것이라 저희가 지울 수 없어요.\n\n'
        '남기고 싶은 학습지가 있다면 탈퇴 전에 화면을 저장해 두세요.',
  ),
  FaqItem(
    question: '결제를 그만두면 만든 학습지도 못 보나요',
    answer: '아니요. 이미 만든 학습지는 영원히 무료예요.\n\n'
        '열람도, 필기도, 복습 알림도 계속 돼요. 장수가 0장이어도, 환불하셨어도 마찬가지예요.\n\n'
        '장수는 "새 학습지를 만드는 권리" 에만 붙어요. 손으로 쓴 것을 인질로 잡는 앱은 '
        '만들지 않으려고 해요.',
  ),
  FaqItem(
    question: '한 번에 여러 장을 만들 수 있나요',
    answer: '아니요. 한 번에 한 장씩만 만들어요. 만드는 중에 새로 요청하면 '
        '"학습지를 만드는 중이에요" 라고 알려 드려요.\n\n'
        '한 장을 만드는 데 저희 서버가 꽤 오래 매달려 있어서, 동시에 여러 장을 받으면 '
        '모두가 느려져요. 하나가 끝나면 바로 다음 것을 만들 수 있어요.',
  ),
];

class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.item});
  final FaqItem item;

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(DsRadius.lg),
        border: Border.all(color: p.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // ExpansionTile 기본 구분선을 지운다. 카드 테두리와 겹쳐 두 줄로 보인다.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          // 접기·펼치기는 스크린리더가 알아야 하는 상태 변화다.
          title: Text(item.question, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
          iconColor: p.textSecondary,
          collapsedIconColor: p.textTertiary,
          tilePadding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
          childrenPadding: const EdgeInsets.fromLTRB(
            DsSpace.s4,
            0,
            DsSpace.s4,
            DsSpace.s4,
          ),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.answer,
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
