import os

application = os.path.abspath(defines['app'])
format = 'UDZO'
filesystem = 'HFS+'
files = [application]
symlinks = {'Applications': '/Applications'}
icon = os.path.join(application, 'Contents', 'Resources', 'AppIcon.icns')
background = defines['background']
hide_extensions = ['AutoShell.app']
window_rect = ((240, 160), (740, 488))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0
icon_size = 104
text_size = 13
icon_locations = {'AutoShell.app': (200, 232), 'Applications': (540, 232)}
include_icon_view_settings = True
include_list_view_settings = False
