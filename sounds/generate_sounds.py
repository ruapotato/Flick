#!/usr/bin/env python3
"""Generate default notification and ringtone sounds for Flick"""

import wave
import struct
import math
import os

SAMPLE_RATE = 44100

def generate_tone(frequency, duration, volume=0.5, fade_in=0.01, fade_out=0.05):
    """Generate a sine wave tone with fade in/out"""
    samples = []
    num_samples = int(SAMPLE_RATE * duration)
    fade_in_samples = int(SAMPLE_RATE * fade_in)
    fade_out_samples = int(SAMPLE_RATE * fade_out)

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sample = math.sin(2 * math.pi * frequency * t) * volume

        # Apply fade in
        if i < fade_in_samples:
            sample *= i / fade_in_samples
        # Apply fade out
        elif i > num_samples - fade_out_samples:
            sample *= (num_samples - i) / fade_out_samples

        samples.append(sample)

    return samples

def generate_chord(frequencies, duration, volume=0.3, fade_in=0.01, fade_out=0.1):
    """Generate a chord (multiple frequencies)"""
    samples = []
    num_samples = int(SAMPLE_RATE * duration)
    fade_in_samples = int(SAMPLE_RATE * fade_in)
    fade_out_samples = int(SAMPLE_RATE * fade_out)

    for i in range(num_samples):
        t = i / SAMPLE_RATE
        sample = sum(math.sin(2 * math.pi * f * t) for f in frequencies) * volume / len(frequencies)

        if i < fade_in_samples:
            sample *= i / fade_in_samples
        elif i > num_samples - fade_out_samples:
            sample *= (num_samples - i) / fade_out_samples

        samples.append(sample)

    return samples

def add_silence(duration):
    """Generate silence"""
    return [0.0] * int(SAMPLE_RATE * duration)

def save_wav(filename, samples):
    """Save samples to a WAV file"""
    with wave.open(filename, 'w') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)

        for sample in samples:
            # Convert to 16-bit integer
            value = int(sample * 32767)
            value = max(-32768, min(32767, value))
            wav.writeframes(struct.pack('<h', value))

    print(f"Generated: {filename}")

def notification_ding():
    """Simple pleasant notification ding - two-tone chime"""
    samples = []
    # High-low chime pattern (C6 -> G5)
    samples.extend(generate_tone(1047, 0.15, 0.4))  # C6
    samples.extend(add_silence(0.05))
    samples.extend(generate_tone(784, 0.2, 0.35))   # G5
    return samples

def notification_soft():
    """Soft notification - gentle chord"""
    # Major chord fading in
    return generate_chord([523, 659, 784], 0.4, 0.3, 0.05, 0.2)  # C5, E5, G5

def notification_bubble():
    """Bubble pop notification"""
    samples = []
    # Quick ascending sweep
    for i in range(5):
        freq = 800 + i * 150
        samples.extend(generate_tone(freq, 0.04, 0.3 - i * 0.03))
    return samples

def notification_bell():
    """Classic bell sound"""
    samples = []
    # Bell with harmonics
    base = 880  # A5
    duration = 0.5
    for harmonic, vol in [(1, 0.5), (2, 0.25), (3, 0.15), (4, 0.1)]:
        harm_samples = generate_tone(base * harmonic, duration, vol, 0.001, 0.3)
        if not samples:
            samples = harm_samples
        else:
            for i in range(len(harm_samples)):
                samples[i] += harm_samples[i]
    # Normalize
    max_val = max(abs(s) for s in samples)
    if max_val > 0:
        samples = [s / max_val * 0.5 for s in samples]
    return samples

def ringtone_classic():
    """Classic phone ring pattern"""
    samples = []
    # Two-tone ring pattern repeated
    for _ in range(4):
        # Ring burst
        samples.extend(generate_chord([440, 480], 0.8, 0.4))
        samples.extend(add_silence(0.4))
        samples.extend(generate_chord([440, 480], 0.8, 0.4))
        samples.extend(add_silence(1.5))
    return samples

def ringtone_modern():
    """Modern melodic ringtone"""
    samples = []
    # Pleasant ascending melody repeated
    notes = [
        (523, 0.2),   # C5
        (587, 0.2),   # D5
        (659, 0.2),   # E5
        (784, 0.4),   # G5
    ]
    for _ in range(3):
        for freq, dur in notes:
            samples.extend(generate_tone(freq, dur, 0.4))
            samples.extend(add_silence(0.05))
        samples.extend(add_silence(0.5))
    return samples

def ringtone_gentle():
    """Gentle ambient ringtone"""
    samples = []
    # Soft pulsing chord
    for _ in range(4):
        samples.extend(generate_chord([392, 494, 587], 1.0, 0.3, 0.2, 0.3))  # G4, B4, D5
        samples.extend(add_silence(0.3))
        samples.extend(generate_chord([440, 554, 659], 1.0, 0.3, 0.2, 0.3))  # A4, C#5, E5
        samples.extend(add_silence(0.5))
    return samples

def ringtone_urgent():
    """Urgent attention-grabbing ringtone"""
    samples = []
    # Fast alternating tones
    for _ in range(6):
        samples.extend(generate_tone(880, 0.15, 0.5))
        samples.extend(generate_tone(1047, 0.15, 0.5))
        samples.extend(add_silence(0.1))
        samples.extend(generate_tone(880, 0.15, 0.5))
        samples.extend(generate_tone(1047, 0.15, 0.5))
        samples.extend(add_silence(0.6))
    return samples

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # Notification sounds
    save_wav(os.path.join(script_dir, "notification_ding.wav"), notification_ding())
    save_wav(os.path.join(script_dir, "notification_soft.wav"), notification_soft())
    save_wav(os.path.join(script_dir, "notification_bubble.wav"), notification_bubble())
    save_wav(os.path.join(script_dir, "notification_bell.wav"), notification_bell())

    # Ringtones
    save_wav(os.path.join(script_dir, "ringtone_classic.wav"), ringtone_classic())
    save_wav(os.path.join(script_dir, "ringtone_modern.wav"), ringtone_modern())
    save_wav(os.path.join(script_dir, "ringtone_gentle.wav"), ringtone_gentle())
    save_wav(os.path.join(script_dir, "ringtone_urgent.wav"), ringtone_urgent())

    print("\nAll sounds generated successfully!")
    print("\nNotification sounds:")
    print("  - notification_ding.wav (default)")
    print("  - notification_soft.wav")
    print("  - notification_bubble.wav")
    print("  - notification_bell.wav")
    print("\nRingtones:")
    print("  - ringtone_classic.wav")
    print("  - ringtone_modern.wav (default)")
    print("  - ringtone_gentle.wav")
    print("  - ringtone_urgent.wav")
