project(
  'claudebar-xfce',
  'c',
  version: '0.1.0',
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

plugin_datadir = join_paths(get_option('prefix'), get_option('datadir'), 'xfce4/panel/plugins')
plugin_libdir  = join_paths(get_option('prefix'), get_option('libdir'), 'xfce4/panel/plugins')

shared_module(
  'claudebar',
  'src/claudebar.c',
  dependencies: [gtk, libxfce4panel, libxfce4util, libxfce4ui, json_glib],
  install: true,
  install_dir: plugin_libdir,
)

install_data(
  'claudebar.desktop',
  install_dir: plugin_datadir,
)
