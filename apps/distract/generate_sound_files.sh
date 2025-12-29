#!/bin/bash
# Generate beep sound files for Distract app
# Creates WAV files for different frequencies and waveforms

SOUND_DIR="/home/david/Flick/apps/distract/sounds"
mkdir -p "$SOUND_DIR"

echo "Generating sound files..."

# Generate beeps for 20 different frequencies (200-800 Hz)
# And 4 different waveforms (sine, square, triangle, sawtooth)

frequencies=(200 250 300 350 400 450 500 550 600 650 700 750 800)
waveforms=("sine" "square" "triangle" "sawtooth")

for freq in "${frequencies[@]}"; do
    for i in "${!waveforms[@]}"; do
        waveform="${waveforms[$i]}"
        output="$SOUND_DIR/beep_${freq}_${i}.wav"

        # Generate 150ms beep with fade in/out
        sox -n -r 22050 -c 1 "$output" synth 0.15 "$waveform" "$freq" fade 0.01 0.15 0.02 vol 0.5

        if [ $? -eq 0 ]; then
            echo "Created: $output"
        else
            echo "Error creating: $output"
        fi
    done
done

echo "Sound file generation complete!"
echo "Generated $(ls -1 $SOUND_DIR/*.wav 2>/dev/null | wc -l) files"
