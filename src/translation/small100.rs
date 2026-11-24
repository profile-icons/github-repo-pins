use super::cache::{AssetSpec, ModelCache, ModelSpec};
use crate::Result;
use anyhow::{Context, ensure};
use ort::{
    session::{Session, SessionInputValue},
    value::{DynValue, Tensor},
};
use serde::Deserialize;
use std::{collections::BTreeMap, fs, path::PathBuf};

const MAX_INPUT_TOKENS: usize = 512;
const INITIAL_MAX_NEW_TOKENS: usize = 512;
const MAX_NEW_TOKENS: usize = 1024;
const EOS: i64 = 2;
const MODEL: ModelSpec = ModelSpec {
    repo: "casawolice/small100-onnx",
    revision: "a0d8498",
    dir: "small100",
};

#[derive(Deserialize)]
struct LanguageTokens {
    lang_to_id: BTreeMap<String, i64>,
}

#[derive(Debug)]
pub(super) struct OutputBudgetExceeded;

impl std::fmt::Display for OutputBudgetExceeded {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SMaLL-100 translation exceeded its output budget")
    }
}

impl std::error::Error for OutputBudgetExceeded {}

pub(super) struct Small100 {
    tokenizer: tokenizers::Tokenizer,
    languages: BTreeMap<String, i64>,
    encoder: Session,
    decoder: Session,
}
impl Small100 {
    pub fn load(cache: &ModelCache) -> Result<Self> {
        init_runtime()?;
        let tokenizer_file: PathBuf =
            cache.file(MODEL, AssetSpec::new("tokenizer.json", "tokenizer.json"))?;
        let lang_file: PathBuf = cache.file(
            MODEL,
            AssetSpec::new("lang_tokens.json", "lang_tokens.json"),
        )?;
        let tokenizer = tokenizers::Tokenizer::from_file(tokenizer_file)
            .map_err(|err| anyhow::anyhow!("SMaLL-100 tokenizer: {err}"))?;
        let languages: LanguageTokens = serde_json::from_slice(&fs::read(lang_file)?)?;
        let encoder_file = cache.file(
            MODEL,
            AssetSpec::new("onnx/encoder_model.onnx", "encoder_model.onnx"),
        )?;
        let decoder_file = cache.file(
            MODEL,
            AssetSpec::new(
                "onnx/decoder_model_merged.onnx",
                "decoder_model_merged.onnx",
            ),
        )?;
        Ok(Self {
            tokenizer,
            languages: languages.lang_to_id,
            encoder: Session::builder()?.commit_from_file(encoder_file)?,
            decoder: Session::builder()?.commit_from_file(decoder_file)?,
        })
    }

    pub fn translate(&mut self, text: &str, target: &str) -> Result<String> {
        let target_id = *self
            .languages
            .get(target)
            .with_context(|| format!("SMaLL-100 does not support target locale {target}"))?;
        let encoded = self
            .tokenizer
            .encode(text, true)
            .map_err(|err| anyhow::anyhow!("SMaLL-100 tokenization: {err}"))?;
        let mut content: Vec<i64> = encoded.get_ids().iter().copied().map(i64::from).collect();
        if content.last() == Some(&EOS) {
            content.pop();
        }
        content.truncate(MAX_INPUT_TOKENS - 2);
        let mut ids = Vec::with_capacity(content.len() + 2);
        ids.push(target_id);
        ids.extend(content);
        ids.push(EOS);
        self.generate(ids)
    }

    fn generate(&mut self, ids: Vec<i64>) -> Result<String> {
        let len = ids.len();
        let mask = Tensor::<i64>::from_array(([1, len], vec![1_i64; len]))?;
        let output = self.encoder.run(ort::inputs![
            "input_ids" => Tensor::from_array(([1, len], ids))?,
            "attention_mask" => mask.view()
        ])?;
        let mut outputs: BTreeMap<String, DynValue> = output
            .into_iter()
            .map(|(name, val)| (name.to_owned(), val))
            .collect();
        let hidden = outputs
            .remove("last_hidden_state")
            .or_else(|| outputs.into_values().next())
            .context("SMaLL-100 encoder returned no hidden state")?;

        let empty_past = Tensor::<f32>::from_array(([1, 16, 1, 64], vec![0.0_f32; 16 * 64]))?;
        let mut cache: BTreeMap<String, DynValue> = BTreeMap::new();
        let mut current = EOS;
        let mut generated: Vec<u32> = Vec::new();
        let mut complete = false;
        for step in 0..MAX_NEW_TOKENS {
            if step == INITIAL_MAX_NEW_TOKENS {
                eprintln!(
                    "::notice::SMaLL-100 exceeded {INITIAL_MAX_NEW_TOKENS} output tokens; extending to {MAX_NEW_TOKENS}"
                );
            }
            let input_ids = Tensor::<i64>::from_array(([1, 1], vec![current]))?;
            let use_cache = Tensor::<bool>::from_array(([1], vec![step > 0]))?;
            let mut feed: Vec<(String, SessionInputValue<'_>)> = Vec::new();
            for input in &self.decoder.inputs {
                let val: SessionInputValue<'_> = match input.name.as_str() {
                    "input_ids" | "decoder_input_ids" => (&input_ids).into(),
                    "encoder_attention_mask" | "attention_mask" => (&mask).into(),
                    "encoder_hidden_states" => (&hidden).into(),
                    "use_cache_branch" => (&use_cache).into(),
                    name if name.starts_with("past_key_values.") && step == 0 => {
                        (&empty_past).into()
                    }
                    name => cache
                        .get(name)
                        .with_context(|| format!("missing decoder state for {name}"))?
                        .into(),
                };
                feed.push((input.name.clone(), val));
            }
            let decoded = self.decoder.run(feed)?;
            let logits = decoded
                .get("logits")
                .context("SMaLL-100 decoder returned no logits")?;
            let (shape, values) = logits.try_extract_tensor::<f32>()?;
            let width = usize::try_from(
                *shape
                    .last()
                    .context("decoder logits missing vocabulary dimension")?,
            )?;
            ensure!(
                width > 0 && width <= values.len(),
                "invalid decoder logits shape"
            );
            let next = values[values.len() - width..]
                .iter()
                .enumerate()
                .filter(|(_, val)| val.is_finite())
                .max_by(|(a_idx, a_val), (b_idx, b_val)| {
                    a_val.total_cmp(b_val).then_with(|| b_idx.cmp(a_idx))
                })
                .map(|(idx, _)| i64::try_from(idx))
                .context("SMaLL-100 decoder returned no finite logits")??;
            if next == EOS {
                complete = true;
                break;
            }
            generated.push(u32::try_from(next)?);
            for (name, val) in decoded {
                if let Some(suffix) = name.strip_prefix("present.")
                    && (step == 0 || !suffix.contains(".encoder."))
                {
                    cache.insert(format!("past_key_values.{suffix}"), val);
                }
            }
            current = next;
        }
        if !complete {
            return Err(OutputBudgetExceeded.into());
        }
        self.tokenizer
            .decode(&generated, true)
            .map_err(|err| anyhow::anyhow!("SMaLL-100 decoding: {err}"))
    }
}

fn init_runtime() -> Result<()> {
    let path: PathBuf = std::env::var_os("ORT_DYLIB_PATH")
        .map(PathBuf::from)
        .context("SMaLL-100 requires ONNX Runtime 1.22: set ORT_DYLIB_PATH")?;
    ensure!(
        path.is_file(),
        "ORT_DYLIB_PATH must point to an ONNX Runtime shared library"
    );
    std::panic::catch_unwind(|| {
        ort::init_from(path.to_string_lossy())
            .with_name("repo-pins")
            .commit()
    })
    .map_err(|_| {
        anyhow::anyhow!("could not load a compatible ONNX Runtime 1.22 shared library")
    })??;
    Ok(())
}
