#!/usr/bin/env python3
"""
Build a Markov chain from the chirunder/text_messages dataset.

This creates a word transition probability model for next-word prediction.
Dataset: https://huggingface.co/datasets/chirunder/text_messages
Credit: chirunder on Hugging Face

Output: A JSON file mapping each word to its most likely next words.
"""

import json
import re
import sys
from collections import defaultdict
from pathlib import Path

def clean_word(word):
    """Clean a word: lowercase, remove most punctuation, keep apostrophes."""
    word = word.lower().strip()
    # Remove leading/trailing punctuation but keep internal apostrophes
    word = re.sub(r"^[^a-z']+", "", word)
    word = re.sub(r"[^a-z']+$", "", word)
    # Remove if too short or just punctuation
    if len(word) < 1 or not any(c.isalpha() for c in word):
        return None
    return word

def process_message(text, bigrams):
    """Process a single message, extracting word pairs."""
    # Split on whitespace and clean
    words = text.split()
    cleaned = []
    for w in words:
        clean = clean_word(w)
        if clean:
            cleaned.append(clean)

    # Extract bigrams
    for i in range(len(cleaned) - 1):
        word1 = cleaned[i]
        word2 = cleaned[i + 1]
        bigrams[word1][word2] += 1

def main():
    print("Building Markov chain from text_messages dataset...")
    print("Dataset credit: chirunder/text_messages on Hugging Face")
    print()

    # Check if we have the datasets library
    try:
        from datasets import load_dataset
    except ImportError:
        print("ERROR: Please install the datasets library:")
        print("  pip install datasets")
        sys.exit(1)

    # Load dataset (this will download it)
    print("Loading dataset (this may take a while on first run)...")
    dataset = load_dataset("chirunder/text_messages", split="train")

    print(f"Loaded {len(dataset)} messages")
    print()

    # Build bigram counts
    bigrams = defaultdict(lambda: defaultdict(int))

    print("Processing messages...")
    for i, item in enumerate(dataset):
        if i % 500000 == 0:
            print(f"  Processed {i:,} messages...")
        process_message(item["text"], bigrams)

    print(f"  Processed {len(dataset):,} messages total")
    print(f"  Found {len(bigrams):,} unique words with transitions")
    print()

    # Convert to probability-sorted lists, keeping top N next words per word
    MAX_NEXT_WORDS = 5  # Keep top 5 most likely next words
    MIN_COUNT = 3  # Minimum count to include a transition
    MIN_WORD_FREQ = 10  # Minimum total frequency for a word to be included

    print(f"Building transition table (top {MAX_NEXT_WORDS} next words per word)...")

    transitions = {}
    for word, next_words in bigrams.items():
        # Calculate total count for this word
        total = sum(next_words.values())
        if total < MIN_WORD_FREQ:
            continue

        # Sort by count and take top N
        sorted_next = sorted(next_words.items(), key=lambda x: -x[1])
        top_next = []
        for next_word, count in sorted_next[:MAX_NEXT_WORDS]:
            if count >= MIN_COUNT:
                top_next.append(next_word)

        if top_next:
            transitions[word] = top_next

    print(f"  Kept {len(transitions):,} words with transitions")
    print()

    # Save to JSON
    output_path = Path(__file__).parent.parent / "shell" / "data" / "markov_chain.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Create compact output with attribution
    output = {
        "_credit": "Built from chirunder/text_messages dataset on Hugging Face",
        "_url": "https://huggingface.co/datasets/chirunder/text_messages",
        "_description": "Word transition probabilities for next-word prediction",
        "transitions": transitions
    }

    print(f"Saving to {output_path}...")
    with open(output_path, "w") as f:
        json.dump(output, f, separators=(",", ":"))  # Compact JSON

    # Also create a Rust-includable version (just the transitions)
    rust_path = Path(__file__).parent.parent / "shell" / "data" / "markov_transitions.json"
    with open(rust_path, "w") as f:
        json.dump(transitions, f, separators=(",", ":"))

    file_size = output_path.stat().st_size / 1024 / 1024
    print(f"  Output size: {file_size:.2f} MB")
    print()
    print("Done!")
    print()
    print("Sample transitions:")
    sample_words = ["i", "you", "the", "want", "going", "love", "can", "have"]
    for word in sample_words:
        if word in transitions:
            print(f"  '{word}' -> {transitions[word]}")

if __name__ == "__main__":
    main()
