# ClaudeBar — Localization

ClaudeBar ships translations for the following languages alongside its English source:

| Language | Code | Native name |
|---|---|---|
| English (source) | `en` | English |
| French | `fr` | Français |
| Dutch | `nl` | Nederlands |
| German | `de` | Deutsch |
| Spanish | `es` | Español |
| Portuguese | `pt` | Português |
| Swedish | `sv` | Svenska |
| Czech | `cs` | Čeština |
| Polish | `pl` | Polski |
| Russian | `ru` | Русский |
| Ukrainian | `uk` | Українська |
| Arabic | `ar` | العربية |
| Persian | `fa` | فارسی |
| Chinese (Simplified) | `zh` | 中文 |
| Japanese | `ja` | 日本語 |
| Korean | `ko` | 한국어 |
| Turkish | `tr` | Türkçe |
| Italian | `it` | Italiano |
| Hindi | `hi` | हिन्दी |

All translations follow each platform's idiomatic format:

| Platform | Format | Files |
|---|---|---|
| GNOME extension | gettext `.po`/`.mo` | `apps/linux/gnome/po/` |
| KDE Plasmoid | gettext `.po`/`.mo` (consumed by `ki18n`) | `apps/linux/kde/po/` |
| Cinnamon applet | gettext `.po`/`.mo` | `apps/linux/cinnamon/po/` |
| XFCE plugin | gettext `.po`/`.mo` | `apps/linux/xfce/po/` |
| MATE applet | gettext `.po`/`.mo` | `apps/linux/mate/po/` |
| Budgie applet | gettext `.po`/`.mo` | `apps/linux/budgie/po/` |
| LXQt plugin | Qt `.ts`/`.qm` | `apps/linux/lxqt/translations/` |
| Rust helper | gettext `.po`/`.mo` (via `gettext-rs`) | `apps/linux/common/claudebar-helper/po/` |
| macOS app | String Catalog (`.xcstrings`) | `apps/macos/Resources/Localizable.xcstrings` |
| Windows app | .NET `.resx` per culture | `apps/windows/Resources/Strings.*.resx` |
| Windows installer (WiX) | `.wxl` per culture | `apps/windows/installer/loc/*.wxl` |

## Contributing translations

The initial translations in v1.3.0 are AI-generated baselines. Native-speaker review is welcome — see [Translations.md](../docs/wiki/Translations.md) for the contribution workflow.
