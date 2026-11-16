# GitHub Repository Pins

Generate public/private user/org repo pin visualizations for GitHub `README.md` with:

* (optional) dynamic ordering
* (optional) selection of any public and (authorized) private repository
* (optional) themes - select from existing, or contribute to the [themes JSON file](https://github.com/profile-icons/readme-repo-pins/blob/main/files/themes.json)
* (optional) background imagery - URL or filepath
* (optional) user contribution statistics
* (optional) i18n translations using [casawolice/small100-onnx](https://huggingface.co/casawolice/small100-onnx)

Pins for private repos navigate to deployed sites if the link is set to the repo description.

# Instructions

Create the workflow `.github/workflows/gen-repo-pins.yml`:

```yaml
name: gen-repo-pins

on:
  schedule:
    - cron: "0 0 * * *"
  workflow_dispatch:

permissions:
  contents: write

jobs:
  update-pins:
    runs-on: ubuntu-26.04

    steps:
      - uses: profile-icons/github-repo-pins@main
        with:
          gh_api_token: ${{ secrets.GH_API_TOKEN || secrets.GITHUB_TOKEN }}  # optional, use default for public repos; PAT for private, org repos
          gh_username: ${{ secrets.GH_USERNAME || github.repository_owner }}  # optional, defaults to repo owner
          theme: ${{ secrets.THEME }}  # optional
          background_image: ${{ secrets.BG_IMG }}  # optional
          num_repo_pins: ${{ secrets.NUM_REPO_PINS }}  # optional
          repo_pin_order: ${{ secrets.REPO_PIN_ORDER }}  # optional
          repo_names_exclusive: ${{ secrets.REPO_NAMES_EXCLUSIVE }}  # optional
          is_exclude_repos_owned: ${{ secrets.IS_EXCLUDE_REPOS_OWNED }}  # optional
          is_exclude_repos_contributed: ${{ secrets.IS_EXCLUDE_REPOS_CONTRIBUTED }}  # optional
          is_contribution_stats: ${{ secrets.IS_CONTRIBUTION_STATS }}  # optional
          translations: ${{ secrets.TRANSLATE }}  # optional 
          hf_token: ${{ secrets.HF_TOKEN }}  # optional
```

## README

Insert the following placeholder into the repo profile `README.md`:

```markdown
<!-- START: REPO-PINS -->
<!-- END: REPO-PINS -->
```

# Configurations (optional)

The repo project was initially created to streamline the display of generated pin visualizations on a
private profile `README.md`, but supports broader use cases with optional configurations and elevation of API privileges.

<details>
<summary>API Token</summary>

The optional `GH_API_TOKEN` configuration is for elevating GitHub GraphQL API privileges with a [personal access token (PAT)](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)
The default [rate limit](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api) when not using a GitHub PAT is 1000 query points per hour and is limited to public repository data.
The rate limit when using a PAT is increased to 5000, and provides access to authorized private repository data so that pins can be generated for both
public and private repositories to both public and private profiles.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `GH_API_TOKEN`
* value: `[PAT]`

where:
* `PAT` is a GitHub personal access token and can be generated [here](https://github.com/settings/tokens) - optional `[]`

> The default `GH_API_TOKEN` is `GITHUB_TOKEN` (1000 GraphQL API query points per hour)

> A `PAT` is required for displaying private repository pins
</details>

<details>
<summary>Username</summary>

The optional `GH_USERNAME` configuration controls which (pinned/owned/contributed to) repositories are displayed by association.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `GH_USERNAME`
* value: `[username]`

where:
* `username` must match the username associated with repositories pinned/owned/contributed to by the user the pin display focuses on - optional `[]`

> The default `GH_USERNAME` is `github.repository_owner` (the username associated with the owner of the repo)

> `GH_USERNAME` is required for displaying pins on an organisation profile
</details>

<details>
<summary>Theme</summary>

The optional `THEME` configuration controls the visual color scheme of the generated SVG pin background, border, text, and icon features.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:
* key: `THEME`
* value (either one of the two formats):
    * `{<owner/repo>: <theme_name>,...,<owner/repo>: <theme_name>}` - individual pin theme(s)
    * `<theme_name>` - single theme for pin(s)

where:
* `owner/repo` matches the owner/repository names in the URL of a given repository - required `<>`
* `theme_name` matches any key in `files/themes.json` - required `<>`

Available `THEME`:
* ayu
* catppuccin
* cobalt2
* dracula
* everforest
* github
* github_high_contrast
* github_soft
* gruvbox
* horizon
* kanagawa
* material
* monokai
* night_owl
* nord
* one_dark
* palenight
* rose_pine
* solarized
* synthwave_84
* tokyo_night
* tomorrow

> The default `THEME` is `github_soft`

#### Examples

Either, `{<owner/repo>: <theme_name>,...,<owner/repo>: <theme_name>}` for individual repo pins:

```text
"{"r055a/r055a": "github_soft","profile-icons/readme-repo-pins": "dracula"}"
```

or, `<theme_name>` for all generated repo pins:

```text
"github_soft"
```
</details>

<details>
<summary>Background Image</summary>

The optional `BG_IMG` configuration controls the embedding of select imagery to the background of the generated SVG pin(s).

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:
* key: `BG_IMG`
* value (either one of the three formats):
    * `{<owner/repo>: <img-config-dict>,...,<owner/repo>: <img-config-dict>}` - individual pin background image(s)
    * `<img-config-dict>` - single background image for pin(s)
    * `<url/filepath>` - single background image for pin(s)

where:
* `owner/repo` matches the owner/repository names in the URL of a given repository - required `<>`
* `img-config-dict` is any stringified dictionary configuration matching the following format
```
{
    "img": <url/filepath>, 
    "align": [align], 
    "mode": [mode], 
    "opacity": [opacity]
}
```
* `url/filepath` is either an image URL or the path to an image file uploaded (to an owned repo) - required `<>`
* `align` is any align keyword value in [preserveAspectRatio](https://developer.mozilla.org/en-US/docs/Web/SVG/Reference/Attribute/preserveAspectRatio#syntax) attribute - optional `[]` (default `xMidYMid`)
* `mode` is any [CSS object-fit](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/object-fit) property value in `[cover, contain, stretch]` - optional `[]` (default `stretch`)
* `opacity` is a float value between `0` and `1.0` - optional `[]` (default `0.25`)

> The default `BG_IMG` is `None` (which defaults to the `THEME` background color)

#### Examples

Either, `{<owner/repo>: <img-config-dict>,...,<owner/repo>: <img-config-dict>}` for individual repo pins:

```text
"{"r055a/r055a": {"img": "https://eg-url.com"},"profile-icons/readme-repo-pins": {"img": "./imgs/eg-path.png"}}"
```

and with optional `{"align": [align], "mode": [mode], "opacity": [opacity]}`

```text
"{"r055a/r055a": {"img": "https://eg-url.com", "align": [align], "mode": [mode], "opacity": [opacity]}"
```

or, `img-config-dict` for all generated repo pins:

```text
{"img": "./imgs/eg-path.png", "align": [align], "mode": [mode], "opacity": [opacity]}"
```

or, background image URL for all generated repo pins:

```text
"https://eg-url.com"
```

or, background image path for all generated repo pins:

```text
"./imgs/eg-path.png"
```
</details>

<details>
<summary>Number</summary>

The optional `NUM_REPO_PINS` configuration controls the maximum possible numb[README.md](README.md)er of repository pins to generate up to a hard limit of `100`.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `NUM_REPO_PINS`
* value: `[num]`

where:
* `num` is any int value greater than `0` - optional `[]`

> The default `NUM_REPO_PINS` is `6`

> Overruled by the `REPO_NAMES_EXCLUSIVE` configuration when default, or the minimum value between both when also set.
</details>

<details>
<summary>Order</summary>

The optional `REPO_PIN_ORDER` configuration controls the dynamic ordering of generated repository pin visualizations.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `REPO_PIN_ORDER`
* value: `[order]`

where:
* `order` is optionally any value in:
    * `stargazers` - the number of stars the repo has
    * `name` - the repo name
    * `created_at` - the datetime the repo is initially created
    * `updated_at` - the datetime the repo is last updated
    * `pushed_at` - the datetime the repo is last pushed to
    * `random` - any random order

> The default `REPO_PIN_ORDER` is `STARGAZERS`

> Overruled by the `REPO_NAMES_EXCLUSIVE` configuration when default, but not when also set.
</details>

<details>
<summary>Repository List</summary>

The optional `REPO_NAMES_EXCLUSIVE` configuration controls the exclusive generation of pins for a given list of repository names.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `REPO_NAMES_EXCLUSIVE`
* value: `<owner/repo>,...,<owner/repo>`

where:
* `owner/repo` matches the owner/repository names in the URL of a given repository - required `<>`
* `<owner/repo>,...,<owner/repo>` is a list of any number of `owner/repo` separated by commas `,`

#### Examples

```text
"r055a/r055a,profile-icons/readme-repo-pins,profile-icons/github-stats-modified"
```
</details>

<details>
<summary>Exclude Owned Repositories (not pinned)</summary>

By default, repository data collected for generating pin visualizations is first those pinned by a user, followed by
other repositories owned by the user, and then other repositories the user has contributed to but does not own.

The optional `IS_EXCLUDE_REPOS_OWNED` configuration controls whether repositories owned by a user but not pinned are excluded.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `IS_EXCLUDE_REPOS_OWNED`
* value: `[is_exclude]`

where:
* `is_exclude` is either `true` (any value) or `false` (empty) - optional `[]`

> The default `IS_EXCLUDE_REPOS_OWNED` is `false`

> Overruled by the `REPO_NAMES_EXCLUSIVE` configuration, as pin visuals are generated only for listed repositories.
</details>

<details>
<summary>Exclude Contributed Repositories (neither owned nor pinned)</summary>

By default, repository data collected for generating pin visualizations is first those pinned by a user, followed by
other repositories owned by the user, and then other repositories the user has contributed to but does not own.

The optional `IS_EXCLUDE_REPOS_CONTRIBUTED` configuration controls whether repositories contributed to but not owned by a user are excluded.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `IS_EXCLUDE_REPOS_CONTRIBUTED`
* value: `[is_exclude]`

where:
* `is_exclude` is either `true` (any value) or `false` (empty) - optional `[]`

> The default `IS_EXCLUDE_REPOS_CONTRIBUTED` is `false`

> Overruled by the `REPO_NAMES_EXCLUSIVE` configuration, as pin visuals are generated only for listed repositories.
</details>

<details>
<summary>Contribution Stats</summary>

The optional `IS_CONTRIBUTION_STATS` configuration controls whether a (user) contribution percentage is appended to
the repository contributor count in the pin footer, and when more than two, includes weighted percentage in parentheses.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `IS_CONTRIBUTION_STATS`
* value: `[is_stats]`

where:
* `is_stats` is either `true` (any value) or `false` (empty) - optional `[]`

> The default `IS_CONTRIBUTION_STATS` is `false`

### Calculations

The actual user's proportion of credited contributions:

$$
P = \frac{A_u}{\sum_{i=1}^{n} A_i} \times 100
$$

The user's contribution weighted relative to the average of all:

$$
W = \frac{p}{p + \frac{1-p}{n-1}} \times 100
$$

Where:
- $A_u$ = credited additions attributed to the user.
- $A_i$ = credited additions attributed to contributor $i$.
- $p = P/100$ = the user's actual contribution share.
- $n$ = number of contributors with positive credited additions.
- $W$ = weighted contribution score (0–100).

</details>

<details>
<summary>Translations</summary>

The optional TRANSLATE configuration controls whether repository pin description text is translated using [casawolice/small100-onnx](https://huggingface.co/casawolice/small100-onnx), and with which locales.

This can be set by creating a GitHub Action with the following key-value field pairs:

* key: `TRANSLATE`
* value (either one of the two formats):
  * `<locale-code>,...,<locale-code>` 
  * `all` - to translate each repo pin description text into all 100 supported languages.

where:
* `locale-code` matches a locale code in the following list - required `<>`
* The default `TRANSLATE` is none/false when either not configured or empty.

The list of available translations and respective locale codes:

```json
{
  "Afrikaans": "af",
  "Albanian": "sq",
  "Amharic": "am",
  "Arabic": "ar",
  "Armenian": "hy",
  "Asturian": "ast",
  "Azerbaijani": "az",
  "Bashkir": "ba",
  "Belarusian": "be",
  "Bengali": "bn",
  "Bosnian": "bs",
  "Breton": "br",
  "Bulgarian": "bg",
  "Burmese": "my",
  "Catalan": "ca",
  "Cebuano": "ceb",
  "Chinese": "zh",
  "Czech": "cs",
  "Danish": "da",
  "Dutch": "nl",
  "English": "en",
  "Estonian": "et",
  "Finnish": "fi",
  "French": "fr",
  "Fulah": "ff",
  "Galician": "gl",
  "Ganda": "lg",
  "Georgian": "ka",
  "German": "de",
  "Greek": "el",
  "Gujarati": "gu",
  "Haitian Creole": "ht",
  "Hausa": "ha",
  "Hebrew": "he",
  "Hindi": "hi",
  "Croatian": "hr",
  "Hungarian": "hu",
  "Icelandic": "is",
  "Igbo": "ig",
  "Iloko": "ilo",
  "Indonesian": "id",
  "Irish": "ga",
  "Italian": "it",
  "Japanese": "ja",
  "Javanese": "jv",
  "Kannada": "kn",
  "Kazakh": "kk",
  "Khmer": "km",
  "Korean": "ko",
  "Lao": "lo",
  "Latvian": "lv",
  "Lingala": "ln",
  "Lithuanian": "lt",
  "Luxembourgish": "lb",
  "Macedonian": "mk",
  "Malagasy": "mg",
  "Malay": "ms",
  "Malayalam": "ml",
  "Marathi": "mr",
  "Mongolian": "mn",
  "Nepali": "ne",
  "Northern Sotho": "ns",
  "Norwegian": "no",
  "Occitan": "oc",
  "Odia": "or",
  "Pashto": "ps",
  "Persian": "fa",
  "Polish": "pl",
  "Portuguese": "pt",
  "Punjabi": "pa",
  "Romanian": "ro",
  "Russian": "ru",
  "Scottish Gaelic": "gd",
  "Serbian": "sr",
  "Sindhi": "sd",
  "Sinhala": "si",
  "Slovak": "sk",
  "Slovenian": "sl",
  "Somali": "so",
  "Spanish": "es",
  "Sundanese": "su",
  "Swahili": "sw",
  "Swati": "ss",
  "Swedish": "sv",
  "Tagalog": "tl",
  "Tamil": "ta",
  "Thai": "th",
  "Tswana": "tn",
  "Turkish": "tr",
  "Ukrainian": "uk",
  "Urdu": "ur",
  "Uzbek": "uz",
  "Vietnamese": "vi",
  "Welsh": "cy",
  "Western Frisian": "fy",
  "Wolof": "wo",
  "Xhosa": "xh",
  "Yiddish": "yi",
  "Yoruba": "yo",
  "Zulu": "zu"
```

</details>

<details>
<summary>Huggingface Token</summary>

The optional `HF_TOKEN` configuration authenticates requests for faster downloading with higher rate limits.

This can be set by creating a [GitHub Action](https://docs.github.com/en/actions) with the following key-value field pairs:

* key: `HF_TOKEN`
* value: `[hf_token]`

where:
* `hf_token` is a unique token code generated from a personal HuggingFace account - optional `[]`
</details>
   

# Build

```bash
cargo build --release --locked
```

# i18n

```bash
bash scripts/setup-onnx.sh
```

# Run

```bash
cargo run --release --locked -- [OPTIONS]
```

# Contribute

Before making an Issue-linked Pull Request, verify it passes CI checks:

```bash
cargo fmt --all
cargo clippy --fix --allow-dirty --allow-staged --all-targets --all-features
```
