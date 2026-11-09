import 'package:flutter/material.dart';
import 'package:runthru/design/design.dart';

/// Builds an error-styled [SnackBar] on the dark transient surface.
///
/// Error SnackBars share the normal dark floating surface ([RunThruTokens.shellInk]
/// background, [RunThruTokens.shellCream] body text — 11.76:1) so the body text
/// always clears the ≥4.5:1 gate. The error semantic is carried by
/// [RunThruTokens.shellError] used as an accent only — a coral left-edge bar and
/// an error icon — which clears the ≥3:1 graphical/action gate on shellInk
/// (3.94:1). A full-coral surface cannot satisfy the body-text gate with the
/// current palette, which is why the accent approach is used instead.
SnackBar errorSnackBar({required String message, SnackBarAction? action}) {
  return SnackBar(
    backgroundColor: RunThruTokens.shellInk,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    // Zero padding so the coral accent bar reaches the rounded edge; the
    // ClipRRect below restores the corner radius and insets the text/icon.
    padding: EdgeInsets.zero,
    content: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Coral left-edge accent bar — full height of the SnackBar.
            Container(width: 4, color: RunThruTokens.shellError),
            const SizedBox(width: 12),
            const Icon(
              Icons.error_outline,
              size: 20,
              color: RunThruTokens.shellError,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  message,
                  style: RunThruTypography.body.copyWith(
                    color: RunThruTokens.shellCream,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    ),
    action: action,
  );
}
