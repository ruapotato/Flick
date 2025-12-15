Almost working:f750f47
cargo build --release --features hwcompose
sudo systemctl stop phosh
sudo systemctl start android-service@hwcomposer.service
EGL_PLATFORM=hwcomposer ~/Flick/shell/target/release/flick --hwcomposer
