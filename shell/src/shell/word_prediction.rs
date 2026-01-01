// Word prediction module for on-screen keyboard
// Provides real-time word suggestions based on prefix matching AND spell-check

use std::collections::HashMap;

/// Word predictor with frequency-based suggestions and spell-check
pub struct WordPredictor {
    /// Dictionary of words with frequency scores
    words: HashMap<String, u32>,
    /// Current word being typed
    current_word: String,
}

/// Calculate Levenshtein edit distance between two strings
/// Used for spell-check suggestions
fn edit_distance(a: &str, b: &str) -> usize {
    let a_chars: Vec<char> = a.chars().collect();
    let b_chars: Vec<char> = b.chars().collect();
    let a_len = a_chars.len();
    let b_len = b_chars.len();

    if a_len == 0 { return b_len; }
    if b_len == 0 { return a_len; }

    // Use two-row algorithm for memory efficiency
    let mut prev_row: Vec<usize> = (0..=b_len).collect();
    let mut curr_row: Vec<usize> = vec![0; b_len + 1];

    for i in 1..=a_len {
        curr_row[0] = i;
        for j in 1..=b_len {
            let cost = if a_chars[i - 1] == b_chars[j - 1] { 0 } else { 1 };
            curr_row[j] = std::cmp::min(
                std::cmp::min(
                    prev_row[j] + 1,      // deletion
                    curr_row[j - 1] + 1,  // insertion
                ),
                prev_row[j - 1] + cost,   // substitution
            );
        }
        std::mem::swap(&mut prev_row, &mut curr_row);
    }

    prev_row[b_len]
}

impl WordPredictor {
    /// Create a new word predictor with a built-in dictionary
    pub fn new() -> Self {
        let mut words = HashMap::new();

        // Common English words sorted by frequency (most common first)
        // This is a curated list of ~500 most common words
        let common_words = [
            // Articles, pronouns, prepositions (highest frequency)
            ("the", 100), ("be", 99), ("to", 98), ("of", 97), ("and", 96),
            ("a", 95), ("in", 94), ("that", 93), ("have", 92), ("I", 91),
            ("it", 90), ("for", 89), ("not", 88), ("on", 87), ("with", 86),
            ("he", 85), ("as", 84), ("you", 83), ("do", 82), ("at", 81),
            ("this", 80), ("but", 79), ("his", 78), ("by", 77), ("from", 76),
            ("they", 75), ("we", 74), ("say", 73), ("her", 72), ("she", 71),
            ("or", 70), ("an", 69), ("will", 68), ("my", 67), ("one", 66),
            ("all", 65), ("would", 64), ("there", 63), ("their", 62), ("what", 61),

            // Common verbs
            ("is", 60), ("are", 59), ("was", 58), ("were", 57), ("been", 56),
            ("being", 55), ("has", 54), ("had", 53), ("having", 52), ("does", 51),
            ("did", 50), ("doing", 49), ("done", 48), ("can", 47), ("could", 46),
            ("should", 45), ("would", 44), ("will", 43), ("shall", 42), ("may", 41),
            ("might", 40), ("must", 39), ("need", 38), ("want", 37), ("like", 36),
            ("love", 35), ("know", 34), ("think", 33), ("see", 32), ("come", 31),
            ("go", 30), ("get", 29), ("make", 28), ("take", 27), ("give", 26),
            ("find", 25), ("tell", 24), ("ask", 23), ("use", 22), ("work", 21),
            ("call", 20), ("try", 19), ("leave", 18), ("put", 17), ("mean", 16),
            ("keep", 15), ("let", 14), ("begin", 13), ("seem", 12), ("help", 11),
            ("show", 10), ("hear", 9), ("play", 8), ("run", 7), ("move", 6),
            ("live", 5), ("believe", 4), ("hold", 3), ("bring", 2), ("happen", 1),

            // Common nouns
            ("time", 60), ("year", 59), ("people", 58), ("way", 57), ("day", 56),
            ("man", 55), ("woman", 54), ("child", 53), ("world", 52), ("life", 51),
            ("hand", 50), ("part", 49), ("place", 48), ("case", 47), ("week", 46),
            ("company", 45), ("system", 44), ("program", 43), ("question", 42), ("work", 41),
            ("government", 40), ("number", 39), ("night", 38), ("point", 37), ("home", 36),
            ("water", 35), ("room", 34), ("mother", 33), ("area", 32), ("money", 31),
            ("story", 30), ("fact", 29), ("month", 28), ("lot", 27), ("right", 26),
            ("study", 25), ("book", 24), ("eye", 23), ("job", 22), ("word", 21),
            ("business", 20), ("issue", 19), ("side", 18), ("kind", 17), ("head", 16),
            ("house", 15), ("service", 14), ("friend", 13), ("father", 12), ("power", 11),
            ("hour", 10), ("game", 9), ("line", 8), ("end", 7), ("member", 6),
            ("law", 5), ("car", 4), ("city", 3), ("community", 2), ("name", 1),

            // More common nouns (animals, food, objects)
            ("dog", 55), ("cat", 54), ("fish", 53), ("bird", 52), ("food", 51),
            ("thing", 50), ("door", 49), ("table", 48), ("chair", 47), ("window", 46),
            ("tree", 45), ("road", 44), ("street", 43), ("school", 42), ("church", 41),
            ("sun", 40), ("moon", 39), ("star", 38), ("sky", 37), ("rain", 36),
            ("snow", 35), ("wind", 34), ("fire", 33), ("earth", 32), ("sea", 31),
            ("beach", 30), ("mountain", 29), ("river", 28), ("lake", 27), ("forest", 26),
            ("cup", 25), ("glass", 24), ("plate", 23), ("bowl", 22), ("knife", 21),
            ("fork", 20), ("spoon", 19), ("bed", 18), ("desk", 17), ("floor", 16),
            ("wall", 15), ("roof", 14), ("garden", 13), ("park", 12), ("shop", 11),
            ("store", 10), ("office", 9), ("bank", 8), ("hotel", 7), ("restaurant", 6),
            ("movie", 5), ("music", 4), ("song", 3), ("art", 2), ("picture", 1),

            // Common adjectives
            ("good", 60), ("new", 59), ("first", 58), ("last", 57), ("long", 56),
            ("great", 55), ("little", 54), ("own", 53), ("other", 52), ("old", 51),
            ("right", 50), ("big", 49), ("high", 48), ("different", 47), ("small", 46),
            ("large", 45), ("next", 44), ("early", 43), ("young", 42), ("important", 41),
            ("few", 40), ("public", 39), ("bad", 38), ("same", 37), ("able", 36),
            ("best", 35), ("better", 34), ("sure", 33), ("free", 32), ("true", 31),
            ("real", 30), ("full", 29), ("nice", 28), ("beautiful", 27), ("happy", 26),
            ("wonderful", 25), ("amazing", 24), ("awesome", 23), ("terrible", 22), ("great", 21),

            // Common adverbs
            ("here", 60), ("there", 59), ("now", 58), ("then", 57), ("today", 56),
            ("tomorrow", 55), ("yesterday", 54), ("always", 53), ("never", 52), ("often", 51),
            ("sometimes", 50), ("usually", 49), ("probably", 48), ("maybe", 47), ("really", 46),
            ("actually", 45), ("definitely", 44), ("certainly", 43), ("absolutely", 42), ("possibly", 41),
            ("quickly", 40), ("slowly", 39), ("already", 38), ("still", 37), ("just", 36),
            ("only", 35), ("also", 34), ("well", 33), ("very", 32), ("too", 31),

            // Technology words (common for phone use)
            ("phone", 50), ("text", 49), ("message", 48), ("email", 47), ("call", 46),
            ("app", 45), ("wifi", 44), ("internet", 43), ("website", 42), ("online", 41),
            ("download", 40), ("upload", 39), ("password", 38), ("username", 37), ("login", 36),
            ("account", 35), ("settings", 34), ("update", 33), ("install", 32), ("delete", 31),
            ("send", 30), ("receive", 29), ("share", 28), ("save", 27), ("open", 26),
            ("close", 25), ("file", 24), ("folder", 23), ("photo", 22), ("video", 21),
            ("camera", 20), ("screen", 19), ("battery", 18), ("charge", 17), ("bluetooth", 16),

            // Greetings and common phrases
            ("hello", 60), ("hi", 59), ("hey", 58), ("thanks", 57), ("thank", 56),
            ("please", 55), ("sorry", 54), ("yes", 53), ("no", 52), ("ok", 51),
            ("okay", 50), ("sure", 49), ("yeah", 48), ("yep", 47), ("nope", 46),
            ("bye", 45), ("goodbye", 44), ("welcome", 43), ("morning", 42), ("afternoon", 41),
            ("evening", 40), ("night", 39), ("today", 38), ("tomorrow", 37), ("later", 36),

            // Question words
            ("who", 60), ("what", 59), ("when", 58), ("where", 57), ("why", 56),
            ("how", 55), ("which", 54), ("whose", 53),

            // More common words
            ("about", 50), ("after", 49), ("again", 48), ("against", 47), ("before", 46),
            ("between", 45), ("both", 44), ("each", 43), ("even", 42), ("every", 41),
            ("few", 40), ("first", 39), ("into", 38), ("just", 37), ("last", 36),
            ("least", 35), ("less", 34), ("many", 33), ("more", 32), ("most", 31),
            ("much", 30), ("never", 29), ("nothing", 28), ("only", 27), ("over", 26),
            ("own", 25), ("same", 24), ("since", 23), ("some", 22), ("still", 21),
            ("such", 20), ("than", 19), ("these", 18), ("those", 17), ("through", 16),
            ("under", 15), ("very", 14), ("while", 13), ("without", 12), ("within", 11),

            // Common command words (useful for terminals)
            ("sudo", 30), ("apt", 29), ("install", 28), ("remove", 27), ("update", 26),
            ("upgrade", 25), ("list", 24), ("show", 23), ("help", 22), ("exit", 21),
            ("quit", 20), ("clear", 19), ("cd", 18), ("ls", 17), ("mkdir", 16),
            ("rm", 15), ("cp", 14), ("mv", 13), ("cat", 12), ("grep", 11),
            ("find", 10), ("echo", 9), ("pwd", 8), ("nano", 7), ("vim", 6),
            ("git", 5), ("push", 4), ("pull", 3), ("commit", 2), ("branch", 1),
        ];

        for (word, freq) in common_words {
            words.insert(word.to_lowercase(), freq);
        }

        Self {
            words,
            current_word: String::new(),
        }
    }

    /// Add a character to the current word
    pub fn add_char(&mut self, ch: char) {
        if ch.is_alphabetic() {
            self.current_word.push(ch.to_lowercase().next().unwrap_or(ch));
        } else {
            // Non-alphabetic character ends the current word
            self.current_word.clear();
        }
    }

    /// Remove last character from current word (backspace)
    pub fn backspace(&mut self) {
        self.current_word.pop();
    }

    /// Clear current word (space, enter, etc.)
    pub fn clear_word(&mut self) {
        self.current_word.clear();
    }

    /// Get current word being typed
    pub fn current_word(&self) -> &str {
        &self.current_word
    }

    /// Get the length of the current word (for backspace count)
    pub fn current_word_len(&self) -> usize {
        self.current_word.len()
    }

    /// Get predictions for the current word
    /// Returns up to 3 predictions: prefix matches first, then spell-check suggestions
    pub fn get_predictions(&self) -> Vec<String> {
        if self.current_word.len() < 1 {
            return vec![];
        }

        let prefix = &self.current_word;
        let word_len = prefix.len();

        // Find all words that start with the prefix (completions)
        let mut prefix_matches: Vec<(&String, &u32)> = self.words
            .iter()
            .filter(|(word, _)| word.starts_with(prefix) && *word != prefix)
            .collect();

        // Sort by frequency (descending)
        prefix_matches.sort_by(|a, b| b.1.cmp(a.1));

        let mut results: Vec<String> = prefix_matches.iter()
            .take(3)
            .map(|(word, _)| (*word).clone())
            .collect();

        // If we have fewer than 3 predictions and word is at least 2 chars,
        // add spell-check suggestions (words with small edit distance)
        if results.len() < 3 && word_len >= 2 {
            // Calculate max allowed edit distance based on word length
            // Short words: 1 edit, medium: 2 edits, long: 3 edits
            let max_distance = if word_len <= 3 { 1 } else if word_len <= 6 { 2 } else { 3 };

            // Get first letter for prioritization
            let first_char = prefix.chars().next();
            let first_two: String = prefix.chars().take(2).collect();

            // Find words with similar length and small edit distance
            let mut fuzzy_matches: Vec<(&String, usize, u32, usize)> = self.words
                .iter()
                .filter(|(word, _)| {
                    // Only consider words of similar length (prefer same length)
                    let len_diff = (word.len() as i32 - word_len as i32).abs();
                    if len_diff > (max_distance as i32) { return false; }
                    // Don't include exact matches or prefix matches (those are already added)
                    if word.starts_with(prefix) { return false; }
                    true
                })
                .filter_map(|(word, freq)| {
                    let distance = edit_distance(prefix, word);
                    if distance <= max_distance && distance > 0 {
                        // Calculate prefix match score (higher = better match)
                        // Words starting with same letters are more likely what user meant
                        let prefix_score = if word.starts_with(&first_two) {
                            2  // Same first 2 letters = best
                        } else if first_char.is_some() && word.chars().next() == first_char {
                            1  // Same first letter = good
                        } else {
                            0  // Different first letter = less likely
                        };
                        Some((word, distance, *freq, prefix_score))
                    } else {
                        None
                    }
                })
                .collect();

            // Sort by: prefix match (desc), then edit distance (asc), then frequency (desc)
            fuzzy_matches.sort_by(|a, b| {
                b.3.cmp(&a.3)  // Higher prefix score first
                    .then_with(|| a.1.cmp(&b.1))  // Lower edit distance first
                    .then_with(|| b.2.cmp(&a.2))  // Higher frequency first
            });

            // Add fuzzy matches to fill up to 3 results
            for (word, _, _, _) in fuzzy_matches {
                if results.len() >= 3 { break; }
                if !results.contains(word) {
                    results.push(word.clone());
                }
            }
        }

        results
    }

    /// Set current word directly (e.g., when prediction is selected)
    pub fn set_word(&mut self, word: &str) {
        self.current_word = word.to_lowercase();
    }

    /// Learn a new word (add to dictionary with low frequency)
    pub fn learn_word(&mut self, word: &str) {
        let word = word.to_lowercase();
        if word.len() >= 2 && word.chars().all(|c| c.is_alphabetic()) {
            // Only learn if word doesn't exist or has very low frequency
            let freq = self.words.get(&word).copied().unwrap_or(0);
            if freq < 10 {
                self.words.insert(word, freq + 1);
            }
        }
    }
}

impl Default for WordPredictor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_predictions() {
        let mut predictor = WordPredictor::new();

        // Type "th"
        predictor.add_char('t');
        predictor.add_char('h');

        let predictions = predictor.get_predictions();
        assert!(!predictions.is_empty());
        assert!(predictions.iter().any(|w| w == "the" || w == "that" || w == "their"));
    }

    #[test]
    fn test_clear_on_space() {
        let mut predictor = WordPredictor::new();

        predictor.add_char('h');
        predictor.add_char('e');
        predictor.add_char('l');
        assert_eq!(predictor.current_word(), "hel");

        predictor.add_char(' ');
        assert_eq!(predictor.current_word(), "");
    }
}
