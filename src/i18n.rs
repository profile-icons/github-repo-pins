use crate::Result;
#[cfg(feature = "translation")]
use serde::Deserialize;
use std::collections::BTreeMap;
#[cfg(feature = "translation")]
#[path = "translation.rs"]
mod native;

pub trait Translator {
    fn translations(&mut self, text: &str) -> Result<BTreeMap<String, String>>;
}
pub struct NoTranslation;
impl Translator for NoTranslation {
    fn translations(&mut self, _text: &str) -> Result<BTreeMap<String, String>> {
        Ok(BTreeMap::new())
    }
}
#[cfg(feature = "translation")]
#[derive(Deserialize)]
struct Translations {
    static_translations: BTreeMap<String, BTreeMap<String, String>>,
    nllb_codes: BTreeMap<String, String>,
}
pub fn create(
    locales: Option<&str>,
    cache: Option<std::path::PathBuf>,
) -> Result<Box<dyn Translator>> {
    let Some(locales) = locales.filter(|locales| !locales.trim().is_empty()) else {
        return Ok(Box::new(NoTranslation));
    };
    #[cfg(feature = "translation")]
    {
        Ok(Box::new(native::NativeTranslator::new(cache, locales)?))
    }
    #[cfg(not(feature = "translation"))]
    {
        let _ = (cache, locales);
        anyhow::bail!(
            "this binary was built without translation; rebuild with the translation feature"
        );
    }
}
