# RunThru Privacy Policy

**Effective date: November 9, 2026**

RunThru is a paced reading app. This policy explains exactly what data the app
touches, where that data goes, and what never leaves your device. It is written
in plain language because you deserve to understand it without a lawyer.

The short version: **your reading content stays on your device.** The only
service that ever receives information about your reading activity is
Instapaper, and only if you connect an Instapaper account yourself.

---

## What stays on your device

### Clipboard text
When you paste or share text into RunThru, the app reads it locally, splits it
into words, and shows it to you. Clipboard reading sessions are ephemeral: the
text is held in memory for the session and is not transmitted anywhere. The
app checks the clipboard only when it is opened or resumed, and only to offer
you the option to read what you copied — it never sends clipboard contents off
the device.

### Local files (PDF and EPUB)
Files you open from your device are read locally. RunThru extracts the text and
stores that extracted text in the app's private cache on your device so the
file opens faster next time. Nothing from your files is uploaded.

### Reading positions, settings, and stats
Your bookmarks, reading speed, reading goals, display preferences, and local
reading statistics (words read, session lengths) are stored on your device
only.

### Diagnostic logs
RunThru keeps a small, on-device log of technical events (for example, "a file
failed to open") to help diagnose problems. These logs do not contain the text
you read, are never transmitted automatically, and are overwritten regularly.

---

## Services you can choose to connect

RunThru works fully without any account. Two optional connections exist, and
each one activates only when you sign in to it yourself.

### Google Drive (inbound only)
If you connect Google Drive, RunThru asks Google for permission to list and
download the documents you pick. The file content travels from Google to your
device for import; RunThru does not upload anything to Drive and does not store
your documents on any server. Your Google sign-in token is stored in your
device's secure storage. Disconnecting Drive in Settings deletes the stored
token.

### Instapaper (the only outbound connection)
If you connect Instapaper, RunThru:

- fetches your bookmark list from the Instapaper API and caches it on your
  device;
- sends your reading progress for an article back to Instapaper — this happens
  when you pause, leave an article, or finish it, so your position stays in
  sync with your Instapaper account;
- archives an article in your Instapaper account when you finish reading it.

This is the only situation in which information about your reading activity
leaves your device, and it goes only to Instapaper, under the account you
connected. Sign-in uses OAuth; your Instapaper password is exchanged directly
with Instapaper for an access token, which is stored in your device's secure
storage. Logging out deletes the stored token.

### Purchasing RunThru Unlock
RunThru Unlock is a one-time in-app purchase handled entirely by the App Store
or Google Play. RunThru never sees your payment details. The store tells the
app only whether this account owns RunThru Unlock, and the app remembers that
on your device. Restoring a purchase asks the store the same question again.

### Shared web links
When you share a web link into RunThru, the app downloads that page over an
encrypted (HTTPS) connection to extract its readable text on your device. The
extracted text is treated like any other local reading content.

---

## What RunThru does not do

- **No analytics services.** The app contains no third-party analytics,
  tracking, or advertising SDKs.
- **No crash-reporting services.** There is no crash-analytics SDK; diagnostic
  logs stay on the device as described above.
- **No ads.** RunThru shows no advertising and shares no data with ad
  networks.
- **No accounts.** RunThru itself has no account system and no server that
  stores your data. Purchases go through your App Store or Google Play
  account.
- **No sale or sharing of data.** RunThru has nothing to sell or share —
  your data is not collected in the first place.

---

## Permissions the app requests

- **Internet** — used only for the optional connections above (Google Drive,
  Instapaper, shared web links).
- **Notifications** (Android 13+) — used only if you enable reading reminders.
- **Motion sensors** — the 3D reading room reads the gyroscope and
  accelerometer on-device to tilt the view. RunThru does not use the camera.

---

## Children

RunThru does not collect personal data from anyone, including children.

---

## Changes to this policy

When this policy changes, the new version ships with the app update and the
effective date above is revised. Each version of the app contains the policy
that applies to it.

---

## Contact

Questions about this policy are welcome. Email mattmacri89@gmail.com.

The current version of this policy is also published at
https://runthruapp.com/privacy.
