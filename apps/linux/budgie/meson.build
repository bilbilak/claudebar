project(
  'claudebar-budgie',
  ['c', 'vala'],
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
)

gtk             = dependency('gtk+-3.0',        version: '>= 3.22')
budgie          = dependency('budgie-1.0',      version: '>= 2')
peas            = dependency('libpeas-1.0')
json_glib       = dependency('json-glib-1.0')

plugin_dir = join_paths(get_option('prefix'), get_option('libdir'), 'budgie-desktop/plugins/claudebar')

shared_library(
  'claudebar',
  'src/ClaudebarPlugin.vala',
  'src/ClaudebarApplet.vala',
  dependencies: [gtk, budgie, peas, json_glib],
  install: true,
  install_dir: plugin_dir,
)

install_data(
  'claudebar.plugin',
  install_dir: plugin_dir,
)
