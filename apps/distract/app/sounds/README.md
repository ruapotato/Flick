# Distract App Sound Files

This directory contains procedurally generated beep sounds for the Distract toddler app.

## Sound Files

- **Frequencies**: 200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800 Hz
- **Waveforms**:
  - 0 = Sine wave (pure, smooth)
  - 1 = Square wave (buzzy, electronic)
  - 2 = Triangle wave (mellow, soft)
  - 3 = Sawtooth wave (bright, brassy)
- **Duration**: 150ms with fade in/out
- **Format**: 16-bit PCM WAV, mono, 22050 Hz

## Regenerating Sounds

To regenerate all sound files, run:

```bash
cd /home/david/Flick/apps/distract
python3 generate_sounds.py
```

This will create 52 WAV files (13 frequencies × 4 waveforms).

## File Naming

Files are named: `beep_<frequency>_<waveform>.wav`

Example: `beep_400_0.wav` is a 400 Hz sine wave beep.
