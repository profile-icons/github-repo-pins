#[path = "translation/cache.rs"]
mod cache;
#[path = "translation/emoji.rs"]
mod emoji;
#[path = "translation/small100.rs"]
mod small100;

use super::{Translations, Translator};
use crate::Result;
use anyhow::{Context, ensure};
use cache::ModelCache;
use emoji::ProtectedText;
use small100::Small100;
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
};

const MODEL_LOCALES: &str = "af am ar ast az ba be bg bn br bs ca ceb cs cy da de el en es et fa ff fi fr fy ga gd gl gu ha he hi hr ht hu hy id ig ilo is it ja jv ka kk km kn ko lb lg ln lo lt lv mg mk ml mn mr ms my ne nl no ns oc or pa pl ps pt ro ru sd si sk sl so sq sr ss su sv sw ta th tl tn tr uk ur uz vi wo xh yi yo zh zu";

fn parse_locales(value: &str) -> Result<Vec<String>> {
    if value
        .split(',')
        .any(|code| code.trim().eq_ignore_ascii_case("all"))
    {
        return Ok(MODEL_LOCALES
            .split_whitespace()
            .map(str::to_owned)
            .collect());
    }
    let supported: BTreeSet<&str> = MODEL_LOCALES.split_whitespace().collect();
    let mut seen = BTreeSet::new();
    let mut result = Vec::new();
    for code in value.split(',') {
        let code = code.trim().to_ascii_lowercase();
        ensure!(
            !code.is_empty(),
            "translation locale list contains an empty entry"
        );
        ensure!(
            supported.contains(code.as_str()),
            "unsupported SMALL100 translation locale: {code}"
        );
        if seen.insert(code.clone()) {
            result.push(code);
        }
    }
    ensure!(
        !result.is_empty(),
        "translation locale list cannot be empty"
    );
    Ok(result)
}

pub(super) struct NativeTranslator {
    translations: Translations,
    locales: Vec<String>,
    cache: ModelCache,
    model: Option<Small100>,
    results: BTreeMap<String, BTreeMap<String, String>>,
}
impl NativeTranslator {
    pub fn new(cache: Option<PathBuf>, locales: &str) -> Result<Self> {
        let locales = parse_locales(locales)?;
        let translations: Translations = serde_json::from_str(include_str!("../files/i18n.json"))?;
        let dir: PathBuf = cache
            .or_else(|| {
                std::env::var_os("XDG_CACHE_HOME")
                    .map(PathBuf::from)
                    .map(|dir| dir.join("repo-pins"))
            })
            .unwrap_or_else(|| PathBuf::from(".repo-pins-cache"));
        Ok(Self {
            translations,
            locales,
            cache: ModelCache::new(dir)?,
            model: None,
            results: BTreeMap::new(),
        })
    }

    fn detect(&self, text: &str) -> String {
        let code = whatlang::detect(text)
            .map(|info| info.lang().code())
            .unwrap_or("eng");
        match code {
            "cmn" => return "zh".to_owned(),
            "ara" => return "ar".to_owned(),
            _ => {}
        }
        self.translations
            .nllb_codes
            .iter()
            .find(|(locale, val)| {
                MODEL_LOCALES
                    .split_whitespace()
                    .any(|supported| supported == locale.as_str())
                    && val.split('_').next() == Some(code)
            })
            .map(|(locale, _)| locale.clone())
            .unwrap_or_else(|| "en".to_owned())
    }
}
impl Translator for NativeTranslator {
    fn translations(&mut self, text: &str) -> Result<BTreeMap<String, String>> {
        if text.trim().is_empty() {
            return Ok(BTreeMap::new());
        }
        if let Some(static_translations) = self
            .translations
            .static_translations
            .get(&text.trim().to_lowercase())
        {
            return Ok(self
                .locales
                .iter()
                .filter_map(|locale| {
                    static_translations
                        .get(locale)
                        .map(|value| (locale.clone(), value.clone()))
                })
                .collect());
        }
        if let Some(result) = self.results.get(text) {
            return Ok(result.clone());
        }
        let protected = ProtectedText::new(text);
        let src = self.detect(&protected.plain_text());
        let mut result = BTreeMap::new();
        for target in &self.locales {
            if *target == src {
                result.insert(target.clone(), text.to_owned());
                continue;
            }
            let translated = protected
                .translate(|run| {
                    if self.model.is_none() {
                        self.model = Some(Small100::load(&self.cache)?);
                    }
                    self.model
                        .as_mut()
                        .context("SMaLL-100 was not initialized")?
                        .translate(run, target)
                })
                .with_context(|| format!("SMaLL-100 translation {src} -> {target}"))?;
            result.insert(target.clone(), translated);
        }
        self.results.insert(text.to_owned(), result.clone());
        Ok(result)
    }
}
