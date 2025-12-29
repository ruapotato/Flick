#!/usr/bin/env python3
"""Generate all sound files for the Distract app"""

import os
import math
import struct

def generate_wave(frequency, duration_ms, waveform_type):
    """Generate PCM audio data for a beep"""
    sample_rate = 22050
    num_samples = int(sample_rate * duration_ms / 1000)
    volume = 0.5

    samples = []
    for i in range(num_samples):
        t = i / sample_rate

        # Envelope for smooth attack and release
        attack_time = 0.01
        release_time = 0.02
        duration_sec = duration_ms / 1000
        envelope = 1.0

        if t < attack_time:
            envelope = t / attack_time
        elif t > duration_sec - release_time:
            envelope = (duration_sec - t) / release_time

        # Generate waveform
        if waveform_type == 0:  # Sine wave
            value = math.sin(2 * math.pi * frequency * t)
        elif waveform_type == 1:  # Square wave
            value = 1.0 if math.sin(2 * math.pi * frequency * t) > 0 else -1.0
        elif waveform_type == 2:  # Triangle wave
            phase = (frequency * t) % 1
            value = (4 * phase - 1) if phase < 0.5 else (3 - 4 * phase)
        elif waveform_type == 3:  # Sawtooth wave
            value = 2 * ((frequency * t) % 1) - 1
        else:
            value = math.sin(2 * math.pi * frequency * t)

        # Apply envelope and volume
        value = value * envelope * volume

        # Convert to 16-bit PCM
        sample = int(value * 32767)
        sample = max(-32768, min(32767, sample))
        samples.append(sample)

    return samples, sample_rate

def create_wav_file(samples, sample_rate, filename):
    """Create a WAV file from PCM samples"""
    num_samples = len(samples)
    num_channels = 1
    sample_width = 2  # 16-bit

    with open(filename, 'wb') as f:
        # RIFF header
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36 + num_samples * sample_width))
        f.write(b'WAVE')

        # fmt chunk
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))  # Chunk size
        f.write(struct.pack('<H', 1))   # Audio format (PCM)
        f.write(struct.pack('<H', num_channels))
        f.write(struct.pack('<I', sample_rate))
        f.write(struct.pack('<I', sample_rate * num_channels * sample_width))
        f.write(struct.pack('<H', num_channels * sample_width))
        f.write(struct.pack('<H', sample_width * 8))

        # data chunk
        f.write(b'data')
        f.write(struct.pack('<I', num_samples * sample_width))
        for sample in samples:
            f.write(struct.pack('<h', sample))

if __name__ == '__main__':
    sound_dir = '/home/david/Flick/apps/distract/sounds'
    os.makedirs(sound_dir, exist_ok=True)

    print("Generating sound files...")

    # Generate beeps for different frequencies and waveforms
    frequencies = [200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 750, 800]
    waveforms = ['sine', 'square', 'triangle', 'sawtooth']
    duration_ms = 150

    count = 0
    for freq in frequencies:
        for wave_idx in range(4):
            filename = f"{sound_dir}/beep_{freq}_{wave_idx}.wav"
            samples, sample_rate = generate_wave(freq, duration_ms, wave_idx)
            create_wav_file(samples, sample_rate, filename)
            print(f"Created: {filename}")
            count += 1

    print(f"\nSound file generation complete! Created {count} files.")
