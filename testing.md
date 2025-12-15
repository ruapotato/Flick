Stop phosh
sudo systemctl start android-service@hwcomposer.service
EGL_PLATFORM=hwcomposer ~/Flick/shell/target/release/flick --hwcomposer
