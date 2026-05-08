# RunThru — Privacy Policy

**Effective**: 2026-05-06
**Last updated**: 2026-05-06
**Contact**: support@runthruapp.com

## Plain-language summary

RunThru is a paced reading app that runs entirely on your device. Your reading
content — PDFs, EPUBs, clipboard text, and articles — stays on your phone. We
do not run analytics SDKs, we do not show ads, and we do not track you. The
only time RunThru talks to the internet is when you choose to sign in to
Instapaper and tap refresh or import; that connection goes to Instapaper and
nowhere else.

## What we collect

Everything in this list lives on your device. Nothing here is sent to us or to
any server we control, because we do not run a server.

- **Reading content** (PDFs, EPUBs, articles, and text you import). Stored in
  the app's documents directory. Clipboard text is held only for the current
  session and discarded when you leave the screen. Stays on your device.
- **Reading sessions** (when a session started, when it ended, how many words
  you read, your average words-per-minute, and the file path of what you were
  reading). Stored locally in app preferences. Capped at the most recent 1000
  sessions — older entries are dropped automatically. Stays on your device.
- **Your preferences** (words-per-minute, theme, spacing, pacing settings, and
  similar choices). Stored locally in app preferences. Stays on your device.
- **Instapaper sign-in tokens**, only if you sign in to Instapaper. Stored in
  your device's secure enclave through `flutter_secure_storage`. Used only to
  call the Instapaper API on your behalf. Stays on your device.
- **Instapaper bookmarks and article text**, only when you tap refresh or
  import. Fetched live from Instapaper, then cached on your device for the
  rest of your session.

## What we do not collect

- We do not collect crash reports.
- We do not use analytics SDKs.
- We do not collect advertising identifiers.
- We do not collect your name, email, phone number, or contacts.
- We do not collect your location.
- We do not sell data — there is no data to sell.

## Third-party services

- **Instapaper** (optional). If you sign in to Instapaper, RunThru uses your
  credentials to fetch your saved articles. Your sign-in tokens are stored in
  your device's secure enclave (`flutter_secure_storage`). RunThru does not
  proxy your tokens through any server we control — the connection is direct
  from your device to Instapaper. Instapaper's privacy policy applies to data
  Instapaper holds: <https://www.instapaper.com/privacy>.

This is the only third-party service RunThru talks to, and it is only active
when you sign in and tap refresh or import.

## Data retention

- **Reading sessions**: kept up to a maximum of 1000. Once you cross that, the
  oldest session is dropped automatically.
- **Preferences**: kept until you clear app data or uninstall RunThru.
- **Reading content**: kept until you delete the file from your library, clear
  app data, or uninstall RunThru.
- **Instapaper tokens**: kept until you sign out of Instapaper inside RunThru,
  clear app data, or uninstall.

## Your rights

You have the following rights over the data RunThru holds on your device.
Because all of that data lives on your device, you can exercise most of these
rights yourself, immediately, without contacting us.

- **See your data**: open the Stats screen to see your reading sessions, or
  use your device's file manager to inspect the app's documents directory.
- **Delete your data**: tap "Clear all data" in Stats to delete reading
  sessions, delete files from the library to remove reading content, sign out
  of Instapaper to discard your tokens, or clear app data / uninstall RunThru
  to remove everything in one step.
- **Take your data with you**: reading content is stored as the original PDF,
  EPUB, or text file in the app's documents directory and can be copied out.
- **Opt out of sale**: not applicable. We do not sell your data.
- **Object or restrict processing**: stop using the relevant feature (for
  example, sign out of Instapaper to stop the only network connection).

If you have questions or want to ask us to do something on your behalf,
contact us using the email or link at the top of this policy.

## Children

RunThru is not designed for children and does not have age-gated features. We
do not knowingly collect data from anyone, including children under 13,
because we do not collect data from anyone — everything stays on the device.
If a child has imported content into RunThru on a shared device, you can
remove it by clearing app data in your operating system settings.

## Changes

If we change this policy, we update the **Effective** and **Last updated**
dates at the top and post the new policy here. We do not have an email list,
so we cannot email you about changes — please check this page if you want to
see the latest version.

## Contact

Questions, requests, or concerns: support@runthruapp.com.
