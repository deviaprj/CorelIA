# Guidelines Qualité Développement

## Standards Code
- MVVM + Riverpod (state mgmt).
- 100% responsive (mobile/web).
- Tests : flutter_test (unit/widget), integration_test (e2e émulateurs).
- Lint : very_good_analysis.
- Perf : Flame charts <16ms frames.

## Tests Auto
- CI GitHub Actions : build/test/deploy staging.
- Émulateur : `flutter emulators --launch` + `flutter drive`.

## Déploiement Auto
- Mobile : Fastlane (APK/App Store Connect).
- Extension : `flutter build web --release` → zip Chrome Store.

## Sécurité/Scale
- Firebase rules strict (user-owned data).
- Rate limiting Functions.
- PWA pour extension (offline cache).

Toujours prioriser vitesse/sync/UX simple.
