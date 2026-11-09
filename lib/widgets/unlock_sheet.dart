import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/services/purchase_service.dart';
import 'package:runthru/widgets/runthru_shell_widgets.dart';

/// What RunThru Unlock adds. Keep in sync with the store listing.
const List<String> runThruUnlockBenefits = [
  'Reading Wins: time, streaks and gentle progress notes',
  'Page ranges: read only the pages you need',
  'The 3D reading room',
];

/// Opens the RunThru Unlock sheet.
Future<void> showUnlockSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: RunThruTokens.shellBase,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const UnlockSheet(),
  );
}

/// One-time purchase sheet: benefits, store price, buy and restore.
class UnlockSheet extends ConsumerWidget {
  /// Creates the sheet.
  const UnlockSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(purchaseControllerProvider);
    final owned = ref.watch(hasPremiumProvider);
    final controller = ref.read(purchaseControllerProvider.notifier);

    final String buyLabel;
    if (owned) {
      buyLabel = 'Unlocked';
    } else if (state.loading) {
      buyLabel = 'Checking the store…';
    } else if (state.flow == PurchaseFlow.pending) {
      buyLabel = 'Waiting for the store…';
    } else if (state.product != null) {
      buyLabel = 'Unlock for ${state.product!.price}';
    } else {
      buyLabel = 'Unlock unavailable';
    }

    final String? note = owned
        ? 'RunThru Unlock is active on this device.'
        : state.message ??
              (!state.loading && !state.storeAvailable
                  ? 'The store is not reachable right now.'
                  : (!state.loading && state.product == null
                        ? 'RunThru Unlock is not available in this store yet.'
                        : null));

    return SafeArea(
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'RunThru Unlock',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'RunThru Unlock',
                  style: RunThruTypography.title.copyWith(
                    color: RunThruTokens.shellTextPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'One payment, yours to keep. No subscription.',
                style: RunThruTypography.body.copyWith(
                  color: RunThruTokens.shellTextSecondary,
                ),
              ),
              const SizedBox(height: 16),
              for (final benefit in runThruUnlockBenefits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const ExcludeSemantics(
                        child: Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: RunThruTokens.shellAccent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          benefit,
                          style: RunThruTypography.body.copyWith(
                            color: RunThruTokens.shellTextPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: RunThruPrimaryButton(
                  icon: owned ? Icons.check : Icons.lock_open,
                  label: buyLabel,
                  onPressed: !owned && state.canBuy ? controller.buy : null,
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      RunThruA11y.minTapTarget,
                      RunThruA11y.minTapTarget,
                    ),
                  ),
                  onPressed:
                      owned ||
                          state.flow == PurchaseFlow.pending ||
                          state.flow == PurchaseFlow.restoring
                      ? null
                      : controller.restore,
                  child: Text(
                    state.flow == PurchaseFlow.restoring
                        ? 'Restoring…'
                        : 'Restore purchase',
                    style: RunThruTypography.body.copyWith(
                      color: RunThruTokens.shellAccent,
                    ),
                  ),
                ),
              ),
              Semantics(
                liveRegion: true,
                child: note == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          note,
                          textAlign: TextAlign.center,
                          style: RunThruTypography.caption.copyWith(
                            color: RunThruTokens.shellTextSecondary,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline prompt shown in place of a locked feature.
class UnlockPrompt extends StatelessWidget {
  /// Creates the prompt.
  const UnlockPrompt({
    super.key,
    required this.title,
    required this.body,
    this.icon = Icons.lock_outline,
  });

  /// Feature name, e.g. 'Reading Wins'.
  final String title;

  /// One sentence on what the feature does.
  final String body;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: 48,
              color: RunThruTokens.shellTextSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              title,
              style: RunThruTypography.title,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: RunThruTypography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          RunThruPrimaryButton(
            icon: Icons.lock_open,
            label: 'See RunThru Unlock',
            onPressed: () => showUnlockSheet(context),
          ),
        ],
      ),
    );
  }
}
