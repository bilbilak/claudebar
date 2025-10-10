project(
  'claudebar-xfce',
  'c',
  version: '0.0.0',
  license: 'GPL-3.0-or-later',
  default_options: [
    'c_std=gnu11',
    'warning_level=2',
  ],
)

gtk          = dependency('gtk+-3.0',          version: '>= 3.22')
libxfce4panel = dependency('libxfce4panel-2.0', version: '>= 4.14')
libxfce4util  = dependency('libxfce4util-1.0')
libxfce4ui    = dependency('libxfce4ui-2')
json_glib     = dependency('json-glib-1.0')

# gettext domain — must match GETTEXT_PACKAGE in src/claudebar.c and the
# basename of the .pot file in po/. Shared with the other Linux panel
# plugins; the .pot file is emitted by scripts/regenerate-translations.py
# from the canonical YAML source.
gettext_domain = 'claudebar'

prefix         = get_option('prefix')
datadir        = get_option('datadir')
localedir      = join_paths(prefix, datadir, 'locale')

plugin_datadir = join_paths(prefix, datadir, 'xfce4/panel/plugins')
plugin_libdir  = join_paths(prefix, get_option('libdir'), 'xfce4/panel/plugins')

c_args = [
  '-DGETTEXT_PACKAGE="' + gettext_domain + '"',
  '-DLOCALEDIR="' + localedir + '"',
  '-DCLAUDEBAR_VERSION="' + meson.project_version() + '"',
]

shared_module(
  'claudebar',
  'src/claudebar.c',
  c_args: c_args,
  dependencies: [gtk, libxfce4panel, libxfce4util, libxfce4ui, json_glib],
  install: true,
  install_dir: plugin_libdir,
)

install_data(
  'claudebar.desktop',
  install_dir: plugin_datadir,
)

# Icon — referenced as `Icon=claudebar` in claudebar.desktop. The shared
# source PNGs at multiple panel-relevant sizes live under
# apps/linux/common/icons/<size>x<size>/; install each into the matching
# hicolor bucket so GTK icon-theme lookup resolves them at every size
# without runtime downscaling.
foreach sz : ['16', '22', '24', '32', '48', '64', '128', '256', '512']
  install_data(
    '../common/icons/' + sz + 'x' + sz + '/claudebar.png',
    install_dir: join_paths(prefix, datadir, 'icons/hicolor/' + sz + 'x' + sz + '/apps'),
  )
endforeach

#
# `po/` contains the .pot template and one <lang>.po per supported language,
# all generated from the canonical source at i18n/strings.yaml by
# scripts/regenerate-translations.py. We compile each .po into a binary .mo
# and install it as claudebar.mo under the standard locale tree so that
# bindtextdomain(GETTEXT_PACKAGE, LOCALEDIR) picks it up at runtime.
#
# Language list lives in po/LINGUAS, one code per line.

subdir('po')

# Refresh the GTK icon-theme cache after a real install so the panel picks
# up our /usr/share/icons/hicolor/.../apps/claudebar.png without a reboot
# or manual `gtk-update-icon-cache` invocation. Skipped under DESTDIR
# (staged install for distro packaging — the package's post-install hook
# is responsible there) and silently no-op when the binary isn't on PATH.
meson.add_install_script(
  'sh', '-c',
  'test -z "$DESTDIR" && command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qtf "$MESON_INSTALL_PREFIX/share/icons/hicolor" || true',
)
