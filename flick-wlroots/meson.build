project('flick', 'c',
  version: '0.1.0',
  license: 'GPL-3.0-or-later',
  default_options: [
    'c_std=c11',
    'warning_level=2',
  ],
)

# Dependencies
wlroots = dependency('wlroots', version: '>=0.17.0')
wayland_server = dependency('wayland-server')
wayland_protocols = dependency('wayland-protocols', version: '>=1.24')
xkbcommon = dependency('xkbcommon')
pixman = dependency('pixman-1')

# Source files
flick_sources = files(
  'src/main.c',
  'src/server.c',
  'src/output.c',
  'src/input.c',
)

# Include directories
flick_inc = include_directories('src')

# Main executable
executable('flick',
  flick_sources,
  include_directories: flick_inc,
  dependencies: [
    wlroots,
    wayland_server,
    xkbcommon,
    pixman,
  ],
  install: true,
)
