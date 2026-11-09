import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// Asset path of the bundled privacy policy (single source of truth is
/// `doc/legal/privacy_policy.md`; it ships with each app version).
const String privacyPolicyAsset = 'doc/legal/privacy_policy.md';

/// Kinds of block the policy renderer understands.
enum PolicyBlockKind { heading, subheading, paragraph, bullet }

/// One rendered block of the privacy policy.
@immutable
class PolicyBlock {
  /// Creates a block.
  const PolicyBlock(this.kind, this.text);

  /// Block kind.
  final PolicyBlockKind kind;

  /// Plain text with markdown emphasis markers removed.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PolicyBlock && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() => 'PolicyBlock($kind, $text)';
}

/// Parses the small markdown subset used by the privacy policy.
///
/// Supports `##`/`###` headings, `- ` bullets with indented continuation
/// lines, and blank-line separated paragraphs. The top-level `#` title,
/// `---` rules and HTML comments are dropped; `**bold**` markers are removed.
List<PolicyBlock> parsePolicyMarkdown(String source) {
  final blocks = <PolicyBlock>[];
  PolicyBlockKind? openKind;
  final buffer = StringBuffer();

  void flush() {
    if (openKind != null && buffer.isNotEmpty) {
      blocks.add(PolicyBlock(openKind!, _stripEmphasis(buffer.toString())));
    }
    openKind = null;
    buffer.clear();
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed == '---' || trimmed.startsWith('<!--')) {
      flush();
      continue;
    }
    if (trimmed.startsWith('# ')) {
      flush();
      continue;
    }
    if (trimmed.startsWith('### ')) {
      flush();
      blocks.add(
        PolicyBlock(PolicyBlockKind.subheading, trimmed.substring(4).trim()),
      );
      continue;
    }
    if (trimmed.startsWith('## ')) {
      flush();
      blocks.add(
        PolicyBlock(PolicyBlockKind.heading, trimmed.substring(3).trim()),
      );
      continue;
    }
    if (trimmed.startsWith('- ')) {
      flush();
      openKind = PolicyBlockKind.bullet;
      buffer.write(trimmed.substring(2).trim());
      continue;
    }
    if (openKind == null) {
      openKind = PolicyBlockKind.paragraph;
    } else {
      buffer.write(' ');
    }
    buffer.write(trimmed);
  }
  flush();
  return blocks;
}

String _stripEmphasis(String text) => text.replaceAll('**', '');

/// Shows the privacy policy bundled with this version of the app.
class PrivacyPolicyScreen extends StatefulWidget {
  /// Creates the screen. [loader] is injectable for tests.
  const PrivacyPolicyScreen({super.key, this.loader});

  /// Loads the policy markdown; defaults to the bundled asset.
  final Future<String> Function()? loader;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  // Loaded once so rebuilds (e.g. text-scale changes) do not blank the page.
  late final Future<String> _policy =
      (widget.loader ?? () => rootBundle.loadString(privacyPolicyAsset))();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RunThruTokens.shellBase,
      body: SafeArea(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Privacy policy screen',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RunThruScreenHeader(
                title: 'Privacy',
                subtitle: 'What RunThru does with your data',
                leading: RunThruHeaderIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Expanded(
                child: FutureBuilder<String>(
                  future: _policy,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            'The privacy policy could not be loaded.',
                            style: RunThruTypography.body.copyWith(
                              color: RunThruTokens.shellTextSecondary,
                            ),
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) return const SizedBox.shrink();
                    final blocks = parsePolicyMarkdown(snapshot.data!);
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: blocks.length,
                      itemBuilder: (context, i) => _PolicyBlockView(blocks[i]),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicyBlockView extends StatelessWidget {
  const _PolicyBlockView(this.block);

  final PolicyBlock block;

  @override
  Widget build(BuildContext context) {
    const primary = RunThruTokens.shellTextPrimary;
    const secondary = RunThruTokens.shellTextSecondary;
    return switch (block.kind) {
      PolicyBlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Semantics(
          header: true,
          child: Text(
            block.text,
            style: RunThruTypography.title.copyWith(color: primary),
          ),
        ),
      ),
      PolicyBlockKind.subheading => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Semantics(
          header: true,
          child: Text(
            block.text,
            style: RunThruTypography.rowTitle.copyWith(color: primary),
          ),
        ),
      ),
      PolicyBlockKind.paragraph => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          block.text,
          style: RunThruTypography.body.copyWith(color: secondary),
        ),
      ),
      PolicyBlockKind.bullet => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Text(
                '•  ',
                style: RunThruTypography.body.copyWith(color: secondary),
              ),
            ),
            Expanded(
              child: Text(
                block.text,
                style: RunThruTypography.body.copyWith(color: secondary),
              ),
            ),
          ],
        ),
      ),
    };
  }
}
