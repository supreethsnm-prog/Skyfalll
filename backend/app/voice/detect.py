"""Spoken-language auto-detection for voice turns (max 2 Bhashini ASR calls).

Background: Bhashini ASR is monolingual per request — `language` selects the
model. Sending Hindi audio as `language=en` (or vice versa) does not error;
it transliterates phonetics into the wrong script and still returns 200.
The frontend therefore sends one global/fallback language plus
`auto_detect=true`, and this module decides whether a single retry in a
better language is worth a second (quota-counted) call.

Two signals, agreed with the user:
1. Script (cheap, offline): Unicode-block majority of the try-1 transcript.
   Unique scripts (Kannada, Telugu, ...) route directly. Shared scripts
   (Devanagari: hi/mr/ne/sa/mai/gom/brx/doi; Perso-Arabic: ur/ks/sd) narrow
   to a family.
2. LLM judge (no Bhashini quota): classifies the try-1 transcript text —
   including romanized forms (e.g. Latin-script Hindi) and Hindi-vs-Marathi
   vocabulary inside Devanagari — into one of the 23 supported codes.

Rule: try-1 in fallback; if script AND judge agree it matches, done (1 call).
Otherwise try-2 in the judged language (max 2 calls total per message).
"""

from __future__ import annotations

from collections.abc import Callable

SUPPORTED_VOICE_LANGUAGES = (
    "as", "bn", "brx", "doi", "en", "gom", "gu", "hi", "kn", "ks",
    "mai", "ml", "mni", "mr", "ne", "or", "pa", "sa", "sat", "sd",
    "ta", "te", "ur",
)

_DEVANAGARI_FAMILY = ("hi", "mr", "ne", "sa", "mai", "gom", "brx", "doi")
_PERSO_ARABIC_FAMILY = ("ur", "ks", "sd")


def script_of(text: str) -> str:
    """Dominant script family of `text`: latin, devanagari, kannada, telugu,
    tamil, malayalam, bengali, gujarati, gurmukhi, odia, perso_arabic, other."""
    counts: dict[str, int] = {}
    for ch in text:
        o = ord(ch)
        if ("A" <= ch <= "Z") or ("a" <= ch <= "z"):
            key = "latin"
        elif 0x0900 <= o <= 0x097F:
            key = "devanagari"
        elif 0x0C80 <= o <= 0x0CFF:
            key = "kannada"
        elif 0x0C00 <= o <= 0x0C7F:
            key = "telugu"
        elif 0x0B80 <= o <= 0x0BFF:
            key = "tamil"
        elif 0x0D00 <= o <= 0x0D7F:
            key = "malayalam"
        elif 0x0980 <= o <= 0x09FF:
            key = "bengali"
        elif 0x0A80 <= o <= 0x0AFF:
            key = "gujarati"
        elif 0x0A00 <= o <= 0x0A7F:
            key = "gurmukhi"
        elif 0x0B00 <= o <= 0x0B7F:
            key = "odia"
        elif 0x0600 <= o <= 0x06FF or 0x0750 <= o <= 0x077F:
            key = "perso_arabic"
        else:
            continue
        counts[key] = counts.get(key, 0) + 1
    if not counts:
        return "other"
    return max(counts, key=lambda k: counts[k])


def script_candidates(script: str) -> tuple[str, ...]:
    if script == "latin":
        return ("en",)
    if script == "devanagari":
        return _DEVANAGARI_FAMILY
    if script == "perso_arabic":
        return _PERSO_ARABIC_FAMILY
    mapping = {
        "kannada": ("kn",),
        "telugu": ("te",),
        "tamil": ("ta",),
        "malayalam": ("ml",),
        "bengali": ("bn",),
        "gujarati": ("gu",),
        "gurmukhi": ("pa",),
        "odia": ("or",),
    }
    return mapping.get(script, ())


_LID_SYSTEM = (
    "You are a language identifier for Indian languages. Given the user's "
    "transcribed speech (which may be romanized, e.g. Hindi written in Latin "
    "letters), reply with ONLY the ISO-639 code of the language spoken, "
    "chosen from: as bn brx doi en gom gu hi kn ks mai ml mni mr ne or pa sa "
    "sat sd ta te ur. No other text. "
    "Code-mixed speech is common: if the text is mostly fluent English with "
    "just one odd non-word (e.g. 'Bislut' in 'Tomorrow in Hubli, how much "
    "will be the Bislut?'), answer en — the odd word is a transliterated "
    "term, not a different language. Only name another language when the "
    "bulk of the text reads as that language (romanized or native script)."
)


def judge_with_llm(
    transcript: str,
    generate: Callable[..., object],
) -> str | None:
    """Ask the LLM which of the 23 codes `transcript` is. Returns None when
    the answer is unusable (caller falls back to script routing). `generate`
    is `llm.generate` (system/history/tools kwargs) to avoid importing LLM
    types here."""
    try:
        turn = generate(system=_LID_SYSTEM, history=[{"role": "user", "content": transcript}], tools=[])
        text = (getattr(turn, "text", "") or "").strip().lower()
    except Exception:
        return None
    # Accept "hi", "hi-devanagari", " lang: mr " etc. — first supported token wins.
    import re

    for token in re.findall(r"[a-z]{2,3}", text):
        if token in SUPPORTED_VOICE_LANGUAGES:
            return token
    return None


def pick_retry_language(
    transcript: str,
    fallback: str,
    judge: Callable[[str], str | None] | None = None,
) -> str | None:
    """Return the try-2 language, or None when try-1 (`fallback`) stands.

    - Unique script routing elsewhere → that language (unless it IS fallback).
    - Shared/ambiguous script → LLM judge; accept only when it names a
      supported code different from fallback (and, for unique-script cases,
      consistent with the script family).
    - Anything unusable → None (keep try-1, show "Heard as <fallback>").
    """
    script = script_of(transcript)
    cands = script_candidates(script)
    judged = judge(transcript) if judge is not None else None
    if judged is not None and judged not in SUPPORTED_VOICE_LANGUAGES:
        judged = None

    if not cands:
        # Script tells us nothing (e.g. digits only): trust the judge if it
        # names something else, else keep try-1.
        if judged and judged != fallback:
            return judged
        return None

    if len(cands) == 1:
        # Unique script. If it matches fallback, done. If the judge agrees
        # (or there is no judge), retry in it. If the judge contradicts a
        # unique script (e.g. romanized Hindi read as Latin), trust the judge
        # — that is exactly the global-en/spoken-Hindi case.
        only = cands[0]
        if only == fallback and (judged is None or judged == fallback):
            return None
        if judged is not None:
            return judged if judged != fallback else None
        return only if only != fallback else None

    # Shared family (Devanagari / Perso-Arabic): the script cannot name the
    # winner — the judge must. Tie-break: fallback if it is in the family
    # (user's own habit wins), else the family's biggest language.
    if judged in cands and judged != fallback:
        return judged
    if fallback in cands:
        return None
    return cands[0]
