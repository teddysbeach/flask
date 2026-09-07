import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onpar_design_system/onpar_design_system.dart';

import '../../core/version_gate.dart';

/// 오픈소스 라이선스.
///
/// Flutter 의 `showLicensePage` 는 pub 패키지의 LICENSE 파일만 모은다.
/// 그런데 우리가 실제로 쓰는 저작물 중 둘은 pub 패키지가 아니라 **생성물로 들어와 있다** —
/// 디자인 토큰(SEED)과 아이콘 path(Untitled UI). 자동으로 잡히지 않으니 직접 고지한다.
/// 고지 의무는 "자동으로 안 잡혀서" 로 면제되지 않는다.
class LicensesScreen extends ConsumerStatefulWidget {
  const LicensesScreen({super.key});

  @override
  ConsumerState<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends ConsumerState<LicensesScreen> {
  @override
  void initState() {
    super.initState();
    registerBundledLicenses();
  }

  @override
  Widget build(BuildContext context) {
    final p = DsTheme.of(context);
    final info = ref.watch(appInfoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('오픈소스 라이선스')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(DsSpace.s4, DsSpace.s4, DsSpace.s4, DsSpace.s12),
          children: [
            Text(
              'ONPAR 은 아래 저작물의 도움을 받아 만들어졌어요.',
              style: dsTextStyle(DsType.body, p.textSecondary),
            ),
            const SizedBox(height: DsSpace.s6),
            for (final (i, notice) in bundledNotices.indexed) ...[
              DsFadeSlide(delay: dsStaggerDelay(i), child: _NoticeCard(notice: notice)),
              const SizedBox(height: DsSpace.s3),
            ],
            const SizedBox(height: DsSpace.s4),
            OutlinedButton(
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'ONPAR',
                applicationVersion: info.valueOrNull?.display,
                applicationLegalese: '© 2026 ONPAR',
              ),
              child: const Text('전체 오픈소스 라이선스 보기'),
            ),
            const SizedBox(height: DsSpace.s4),
            Text(
              '위 목록에는 앱이 쓰는 모든 패키지의 라이선스 전문이 들어 있어요.',
              style: dsTextStyle(DsType.caption, p.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class BundledNotice {
  const BundledNotice({
    required this.name,
    required this.license,
    required this.copyright,
    required this.usage,
    required this.text,
  });

  final String name;
  final String license;
  final String copyright;

  /// 우리가 이것을 어디에 쓰는지. 사용자가 아니라 우리 자신을 위한 기록이기도 하다.
  final String usage;
  final String text;
}

/// pub 패키지가 아니라 소스에 섞여 들어온 저작물. 여기 없으면 아무 데도 표시되지 않는다.
const bundledNotices = <BundledNotice>[
  BundledNotice(
    name: 'SEED Design System',
    license: 'Apache License 2.0',
    copyright: 'Copyright 2025 주식회사 당근마켓',
    usage: '색·간격·타이포그래피 토큰의 원본이에요. 앱과 학습지가 같은 값을 쓰도록 '
        'design/design_tokens.json 을 거쳐 코드로 생성돼 있어요.',
    text: 'SEED Design System\n'
        'Copyright 2025 주식회사 당근마켓 (Danggeun Market Inc.)\n\n'
        'Licensed under the Apache License, Version 2.0 (the "License");\n'
        'you may not use this file except in compliance with the License.\n'
        'You may obtain a copy of the License at\n\n'
        '    http://www.apache.org/licenses/LICENSE-2.0\n\n'
        'Unless required by applicable law or agreed to in writing, software\n'
        'distributed under the License is distributed on an "AS IS" BASIS,\n'
        'WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.\n'
        'See the License for the specific language governing permissions and\n'
        'limitations under the License.',
  ),
  BundledNotice(
    name: 'Untitled UI Icons (untitledui-js)',
    license: 'MIT License',
    copyright: 'Copyright (c) 2025 Emmanuel C. Alozie',
    usage: '앱 곳곳의 아이콘이에요. 필요한 아이콘의 SVG path 만 골라 코드로 생성해 쓰고 있어요.',
    text: 'Untitled UI Icons — untitledui-js\n'
        'Copyright (c) 2025 Emmanuel C. Alozie\n\n'
        'Permission is hereby granted, free of charge, to any person obtaining a copy\n'
        'of this software and associated documentation files (the "Software"), to deal\n'
        'in the Software without restriction, including without limitation the rights\n'
        'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n'
        'copies of the Software, and to permit persons to whom the Software is\n'
        'furnished to do so, subject to the following conditions:\n\n'
        'The above copyright notice and this permission notice shall be included in all\n'
        'copies or substantial portions of the Software.\n\n'
        'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n'
        'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n'
        'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n'
        'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n'
        'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n'
        'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n'
        'SOFTWARE.',
  ),
];

bool _registered = false;

/// `showLicensePage` 목록에도 두 저작물이 나오게 등록한다.
/// 화면을 안 열고 라이선스 페이지로 바로 가는 경로가 생겨도 빠지지 않게, 등록은 여기서 한 번만 한다.
void registerBundledLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    for (final n in bundledNotices) {
      yield LicenseEntryWithLineBreaks([n.name], n.text);
    }
  });
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final BundledNotice notice;

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
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: DsSpace.s4, vertical: DsSpace.s2),
          title: Text(notice.name, style: dsTextStyle(DsType.bodyLg, p.textPrimary)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: DsSpace.s1),
            child: Text(
              '${notice.license} · ${notice.copyright}',
              style: dsTextStyle(DsType.caption, p.textSecondary),
            ),
          ),
          iconColor: p.textSecondary,
          collapsedIconColor: p.textTertiary,
          childrenPadding: const EdgeInsets.fromLTRB(DsSpace.s4, 0, DsSpace.s4, DsSpace.s4),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notice.usage, style: dsTextStyle(DsType.body, p.textSecondary)),
            const SizedBox(height: DsSpace.s4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(DsSpace.s3),
              decoration: BoxDecoration(
                color: p.surfaceSunken,
                borderRadius: BorderRadius.circular(DsRadius.md),
              ),
              child: SelectableText(
                notice.text,
                style: dsTextStyle(DsType.code, p.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
