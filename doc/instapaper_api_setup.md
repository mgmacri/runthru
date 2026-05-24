# Instapaper API Setup

RunThru uses Instapaper's documented Full API with OAuth 1.0a request signing
and xAuth token acquisition. Instapaper's current documentation says xAuth is
the only way to get an access token for the Full API; RunThru does not implement
browser OAuth, OAuth 2, redirect callbacks, or browser-cookie reuse.

Builds that enable Instapaper must provide the consumer credentials as
dart-defines:

```sh
flutter build apk --release \
  --dart-define=INSTAPAPER_CONSUMER_KEY=... \
  --dart-define=INSTAPAPER_CONSUMER_SECRET=...
```

```sh
flutter build ios --release \
  --dart-define=INSTAPAPER_CONSUMER_KEY=... \
  --dart-define=INSTAPAPER_CONSUMER_SECRET=...
```

The app reports whether each value is present in debug diagnostics, but never
prints the values. Missing values produce a setup/configuration error before
any user credential exchange is attempted.
