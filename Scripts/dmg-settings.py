"""Finder layout for the ClipNest clipboard-themed installer."""
import os
app = os.path.abspath(defines['app'])
files = [(app, 'ClipNest.app'), (os.path.abspath(defines['license']), 'LICENSE')]
symlinks = {'应用程序': '/Applications'}
hide = ['LICENSE']
hide_extensions = []  # Keep the signed app free of FinderInfo attributes.
icon = os.path.abspath(defines['icon'])
background = os.path.abspath(defines['background'])
format = 'UDZO'
filesystem = 'HFS+'
size = '64m'
window_rect = ((180, 160), (800, 600))
show_status_bar = False
show_toolbar = False
show_tab_view = False
show_pathbar = False
show_sidebar = False
default_view = 'icon-view'
arrange_by = None
icon_size = 88
text_size = 13
label_pos = 'bottom'
icon_locations = {'ClipNest.app': (228, 285), '应用程序': (572, 285)}
show_icon_preview = False
show_item_info = False
