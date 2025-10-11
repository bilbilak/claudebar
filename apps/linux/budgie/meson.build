project(
  'claudebar-budgie',
  ['c', 'vala'],
  version: '0.0.0',
  license: 'GPL-3.0-or-later',
)

i18n = import('i18n')


# Shared with every other gettext-based ClaudeBar platform (gnome, kde, cinnamon,
# xfce, mate) so a single .mo per language covers them all when installed
# system-wide. MUST match:
#   - the .pot/.mo basename (po/claudebar.pot, claudebar.mo)
#   - the `domain:` field in scripts/regenerate-translations.py for `budgie`
#   - the Intl.textdomain() call in src/ClaudebarPlugin.vala
gettext_package = 'claudebar'
localedir       = join_paths(get_option('prefix'), get_option('datadir'), 'locale')

gtk             = dependency('gtk+-3.0',        version: '>= 3.22')
# Budgie 10.10+ (Solus, recent Buddies of Budgie spins) renamed the plugin
# pkg-config from `budgie-1.0` to `budgie-2.0` and switched to libpeas-2.
# The API symbols we use (Budgie.Plugin, Budgie.Applet, Budgie.PanelPosition,
# Peas.ObjectModule) are stable across both. Budgie-2 transitively loads
# libpeas-2.vapi, so the matching libpeas must come from the same major
# series — mixing libpeas-1.0 + libpeas-2 vapi files breaks Vala compile.
budgie_v2 = false
budgie = dependency('budgie-2.0', required: false)
if budgie.found()
  budgie_v2 = true
  peas = dependency('libpeas-2')
else
  budgie = dependency('budgie-1.0', version: '>= 2')
  peas   = dependency('libpeas-1.0')
endif
json_glib       = dependency('json-glib-1.0')

# Budgie 2.x removed `uuid` as a construct property of Budgie.Applet — the
# panel manages it via the plugin factory. The Vala source guards the
# Object(uuid: uuid) call on this define.
vala_args = ['--target-glib=2.50']
if budgie_v2
  vala_args += ['-D', 'BUDGIE_2']
endif

plugin_dir = join_paths(get_option('prefix'), get_option('libdir'), 'budgie-desktop/plugins/claudebar')

# Generate config.vala so Vala code can reference GETTEXT_PACKAGE / LOCALEDIR
# as compile-time constants (Config.GETTEXT_PACKAGE, Config.LOCALEDIR).
conf = configuration_data()
conf.set_quoted('GETTEXT_PACKAGE', gettext_package)
conf.set_quoted('LOCALEDIR',       localedir)

config_vala = configure_file(
  input:         'src/config.vala.in',
  output:        'config.vala',
  configuration: conf,
)

shared_library(
  'claudebar',
  'src/ClaudebarPlugin.vala',
  'src/ClaudebarApplet.vala',
  config_vala,
  dependencies: [gtk, budgie, peas, json_glib],
  vala_args: vala_args,
  c_args: [
    '-DGETTEXT_PACKAGE="' + gettext_package + '"',
  ],
  install: true,
  install_dir: plugin_dir,
)

install_data(
  'claudebar.plugin',
  install_dir: plugin_dir,
)

# Icon — referenced as `Icon=claudebar` in claudebar.plugin. The shared
# source PNGs at multiple panel-relevant sizes live under
# apps/linux/common/icons/<size>x<size>/; install each into the matching
# hicolor bucket so GTK icon-theme lookup resolves them at every size.
foreach sz : ['16', '22', '24', '32', '48', '64', '128', '256', '512']
  install_data(
    '../common/icons/' + sz + 'x' + sz + '/claudebar.png',
    install_dir: join_paths(get_option('prefix'), get_option('datadir'), 'icons/hicolor/' + sz + 'x' + sz + '/apps'),
  )
endforeach

# Translations — compile po/*.po into installed .mo files under $datadir/locale.
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
