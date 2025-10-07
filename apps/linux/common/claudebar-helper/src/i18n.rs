//! gettext initialization for claudebar-helper.
//!
//! Binds the `claudebar-helper` text domain to either the user's local install
//! (`~/.local/share/locale`) when present, or `/usr/share/locale` as the
//! system fallback. All other modules call `gettextrs::gettext()` (or the
//! `gettext!` macro) directly — this module only handles setup.
//!
//! `.po` sources live in `po/` and are generated from `i18n/strings.yaml`
//! by `scripts/regenerate-translations.py helper`. The Makefile's `install`
//! target compiles them to `.mo` and copies them into `LC_MESSAGES`.

use gettextrs::{bind_textdomain_codeset, bindtextdomain, setlocale, textdomain, LocaleCategory};

pub const TEXT_DOMAIN: &str = "claudebar-helper";

pub fn init() {
    // Honour the user's locale env (LC_ALL / LC_MESSAGES / LANG). Failure here
    // is non-fatal — gettext will simply fall back to the C locale and the
    // English msgids embedded in the binary will be shown.
    let _ = setlocale(LocaleCategory::LcAll, "");

    // Prefer a per-user install dir (matches `make install-helper` which lives
    // entirely under $HOME), and fall back to /usr/share/locale for packaged
    // system-wide installs (distro packages, AUR, RPM, etc.).
    let user_locale_dir = dirs::home_dir()
        .map(|h| h.join(".local/share/locale"))
        .filter(|p| p.exists());
    let bind_result = if let Some(dir) = user_locale_dir {
        bindtextdomain(TEXT_DOMAIN, dir)
    } else {
        bindtextdomain(TEXT_DOMAIN, "/usr/share/locale")
    };
    let _ = bind_result;

    let _ = bind_textdomain_codeset(TEXT_DOMAIN, "UTF-8");
    let _ = textdomain(TEXT_DOMAIN);
}
