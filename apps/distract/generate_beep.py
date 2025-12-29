#!/usr/bin/env python3
"""
Generate procedural beep sounds for the Distract app
Usage: python3 generate_beep.py <frequency> <duration_ms> <volume> <waveform_type>
Output: Plays audio directly to system
"""

import sys
import math
import struct
import subprocess
import tempfile
import os

def generate_wave(frequency, duration_ms, volume, waveform_type):
    """Generate PCM audio data for a beep"""
    sample_rate = 22050
    num_samples = int(sample_rate * duration_ms / 1000)

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

def play_wav(filename):
    """Play WAV file using available system player"""
    players = ['paplay', 'aplay', 'ffplay -nodisp -autoexit']
    for player in players:
        try:
            cmd = player.split() + [filename]
            subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except FileNotFoundError:
            continue
    return False

if __name__ == '__main__':
    if len(sys.argv) < 5:
        print("Usage: generate_beep.py <freq> <duration_ms> <volume> <wave_type>")
        sys.exit(1)

    frequency = float(sys.argv[1])
    duration_ms = int(sys.argv[2])
    volume = float(sys.argv[3])
    waveform_type = int(sys.argv[4])

    # Generate audio
    samples, sample_rate = generate_wave(frequency, duration_ms, volume, waveform_type)

    # Create temporary WAV file
    fd, temp_file = tempfile.mkstemp(suffix='.wav', prefix='distract_beep_')
    os.close(fd)

    create_wav_file(samples, sample_rate, temp_file)

    # Play the file
    if play_wav(temp_file):
        # Schedule cleanup after a delay
        import time
        import threading
        def cleanup():
            time.sleep(0.5)
            try:
                os.unlink(temp_file)
            except:
                pass
        threading.Thread(target=cleanup, daemon=True).start()
    else:
        # Clean up immediately if playback failed
        try:
            os.unlink(temp_file)
        except:
            pass
