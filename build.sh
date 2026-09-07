meson setup build
meson compile -C build
meson install -C build
sudo ln -s /usr/local/lib/thunarx-3/thunar-archive-plugin.so /usr/lib/thunarx-3/
