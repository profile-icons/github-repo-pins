use crate::Result;
use anyhow::ensure;
use regex::Regex;
use std::sync::LazyLock;
use unicode_segmentation::UnicodeSegmentation;

static EMOJI_MARKER: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"[\p{Extended_Pictographic}\p{Emoji_Presentation}\p{Regional_Indicator}]")
        .expect("valid Unicode emoji character classes")
});

fn is_emoji_cluster(grapheme: &str) -> bool {
    EMOJI_MARKER.is_match(grapheme) || grapheme.contains('\u{20e3}')
}

struct Part<'a> {
    value: &'a str,
    emoji: bool,
}

pub(super) struct ProtectedText<'a> {
    parts: Vec<Part<'a>>,
}

impl<'a> ProtectedText<'a> {
    pub fn new(input: &'a str) -> Self {
        let mut parts = Vec::new();
        let mut run_start = 0;
        let mut run_emoji = None;
        for (start, grapheme) in input.grapheme_indices(true) {
            let emoji = is_emoji_cluster(grapheme);
            if let Some(previous) = run_emoji
                && emoji != previous
            {
                parts.push(Part {
                    value: &input[run_start..start],
                    emoji: previous,
                });
                run_start = start;
            }
            run_emoji = Some(emoji);
        }
        if let Some(emoji) = run_emoji {
            parts.push(Part {
                value: &input[run_start..],
                emoji,
            });
        }
        Self { parts }
    }

    pub fn plain_text(&self) -> String {
        self.parts
            .iter()
            .filter(|part| !part.emoji)
            .map(|part| part.value)
            .collect()
    }

    pub fn translate<F>(&self, mut translate_text: F) -> Result<String>
    where
        F: FnMut(&str) -> Result<String>,
    {
        let mut output = String::new();
        for part in &self.parts {
            if part.emoji || !part.value.chars().any(char::is_alphabetic) {
                output.push_str(part.value);
                continue;
            }
            let trimmed = part.value.trim();
            let start = part.value.find(trimmed).expect("trimmed substring exists");
            let end = start + trimmed.len();
            output.push_str(&part.value[..start]);
            let translated = translate_text(trimmed)?;
            ensure!(
                !translated.trim().is_empty(),
                "SMaLL-100 returned empty text"
            );
            output.push_str(translated.trim());
            output.push_str(&part.value[end..]);
        }
        Ok(output)
    }
}
