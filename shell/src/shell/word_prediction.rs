// Word prediction module for on-screen keyboard
// Uses libpresage for intelligent predictive text entry with fallback to simple dictionary

use super::presage::Presage;
use std::collections::HashMap;

/// Word predictor with presage backend and dictionary fallback
pub struct WordPredictor {
    /// Presage instance for intelligent prediction
    presage: Option<Presage>,
    /// Fallback dictionary of words with frequency scores
    fallback_words: HashMap<String, u32>,
    /// Text context before cursor (what user has typed)
    past_context: String,
    /// Current word being typed (extracted from past_context)
    current_word: String,
}

/// Calculate Levenshtein edit distance between two strings
/// Used for spell-check suggestions in fallback mode
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
    /// Create a new word predictor, attempting to use presage first
    pub fn new() -> Self {
        // Try to initialize presage
        let presage = match Presage::new() {
            Ok(p) => {
                tracing::info!("Presage initialized successfully for word prediction");
                Some(p)
            }
            Err(e) => {
                tracing::warn!("Failed to initialize presage, using fallback dictionary: {}", e);
                None
            }
        };

        let mut fallback_words = HashMap::new();

        // Common English words sorted by frequency (most common first)
        // This is used as fallback when presage is unavailable
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
            fallback_words.insert(word.to_lowercase(), freq);
        }

        Self {
            presage,
            fallback_words,
            past_context: String::new(),
            current_word: String::new(),
        }
    }

    /// Extract the current word from the end of the past context
    fn update_current_word(&mut self) {
        // Find the last word in the context
        self.current_word = self.past_context
            .chars()
            .rev()
            .take_while(|c| c.is_alphabetic())
            .collect::<String>()
            .chars()
            .rev()
            .collect();
    }

    /// Add a character to the context
    pub fn add_char(&mut self, ch: char) {
        self.past_context.push(ch);
        self.update_current_word();

        // Update presage context
        if let Some(ref mut presage) = self.presage {
            presage.set_context(&self.past_context, "");
        }
    }

    /// Remove last character from context (backspace)
    pub fn backspace(&mut self) {
        self.past_context.pop();
        self.update_current_word();

        // Update presage context
        if let Some(ref mut presage) = self.presage {
            presage.set_context(&self.past_context, "");
        }
    }

    /// Clear current word (space, enter, etc. - but keep context)
    pub fn clear_word(&mut self) {
        self.current_word.clear();
    }

    /// Clear all context (e.g., when switching focus)
    pub fn clear_context(&mut self) {
        self.past_context.clear();
        self.current_word.clear();

        if let Some(ref mut presage) = self.presage {
            presage.set_context("", "");
        }
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
    /// Returns up to 3 predictions
    pub fn get_predictions(&self) -> Vec<String> {
        if self.current_word.len() < 1 {
            return vec![];
        }

        // Try presage first
        if let Some(ref presage) = self.presage {
            let predictions = presage.predict();
            if !predictions.is_empty() {
                // Limit to 3 predictions
                return predictions.into_iter().take(3).collect();
            }
        }

        // Fallback to dictionary-based prediction
        self.get_fallback_predictions()
    }

    /// Fallback prediction using simple dictionary
    fn get_fallback_predictions(&self) -> Vec<String> {
        let prefix = &self.current_word;
        let word_len = prefix.len();

        // Find all words that start with the prefix (completions)
        let mut prefix_matches: Vec<(&String, &u32)> = self.fallback_words
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
            let max_distance = if word_len <= 3 { 1 } else if word_len <= 6 { 2 } else { 3 };

            // Find words with similar length and small edit distance
            let mut fuzzy_matches: Vec<(&String, usize, u32)> = self.fallback_words
                .iter()
                .filter(|(word, _)| {
                    let len_diff = (word.len() as i32 - word_len as i32).abs();
                    if len_diff > (max_distance as i32) { return false; }
                    if word.starts_with(prefix) { return false; }
                    true
                })
                .filter_map(|(word, freq)| {
                    let distance = edit_distance(prefix, word);
                    if distance <= max_distance && distance > 0 {
                        Some((word, distance, *freq))
                    } else {
                        None
                    }
                })
                .collect();

            // Sort by edit distance first, then by frequency
            fuzzy_matches.sort_by(|a, b| {
                a.1.cmp(&b.1).then_with(|| b.2.cmp(&a.2))
            });

            // Add fuzzy matches to fill up to 3 results
            for (word, _, _) in fuzzy_matches {
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
        // Replace the current word in the context
        let word_len = self.current_word.len();
        for _ in 0..word_len {
            self.past_context.pop();
        }
        self.past_context.push_str(word);
        self.current_word = word.to_lowercase();

        // Update presage context
        if let Some(ref mut presage) = self.presage {
            presage.set_context(&self.past_context, "");
        }
    }

    /// Learn a new word (add to dictionary / teach presage)
    pub fn learn_word(&mut self, word: &str) {
        // Teach presage
        if let Some(ref presage) = self.presage {
            presage.learn(word);
        }

        // Also add to fallback dictionary
        let word = word.to_lowercase();
        if word.len() >= 2 && word.chars().all(|c| c.is_alphabetic()) {
            let freq = self.fallback_words.get(&word).copied().unwrap_or(0);
            if freq < 10 {
                self.fallback_words.insert(word, freq + 1);
            }
        }
    }

    /// Check if presage is available
    pub fn has_presage(&self) -> bool {
        self.presage.is_some()
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
        // Should have at least some predictions (presage or fallback)
        // Note: presage might not be available in test environment
        if !predictor.has_presage() {
            assert!(!predictions.is_empty());
            assert!(predictions.iter().any(|w| w == "the" || w == "that" || w == "their"));
        }
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

    #[test]
    fn test_context_tracking() {
        let mut predictor = WordPredictor::new();

        predictor.add_char('h');
        predictor.add_char('e');
        predictor.add_char('l');
        predictor.add_char('l');
        predictor.add_char('o');
        predictor.add_char(' ');
        predictor.add_char('w');
        predictor.add_char('o');

        assert_eq!(predictor.current_word(), "wo");
    }
}
