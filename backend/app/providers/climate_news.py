"""Climate/weather-disaster news headlines from around the world.

Backs the Discover tab, which the user asked to work "like the home page
of a news outlet" — a feed of current climate news, not a single source's
opinion. Google News' public RSS search endpoint needs no API key, covers
worldwide outlets, and returns a real per-outlet byline in each item's
title ("Headline - Source"), which is split out below so the UI can show
outlet attribution the way a news app does.

Parses with `defusedxml` rather than the stdlib `xml.etree.ElementTree`
directly: the stdlib XML parser resolves external entities by default,
which is an XXE risk for any XML pulled from the network. defusedxml is a
drop-in wrapper that disables that resolution.
"""

import logging
from dataclasses import dataclass

import httpx
from defusedxml import ElementTree

logger = logging.getLogger(__name__)

NEWS_BASE_URL = "https://news.google.com/rss/search"

# English results, dateline India — the app's audience — but a worldwide
# query so the feed reads as "climate news from around the world", not
# only Indian coverage.
_QUERY_PARAMS = {
    "q": "climate OR weather disaster OR extreme weather",
    "hl": "en-IN",
    "gl": "IN",
    "ceid": "IN:en",
}

_USER_AGENT = "WeatherGPT/0.1 (SIH 2026 hackathon project)"


@dataclass
class NewsItemData:
    title: str
    source: str | None
    link: str
    published_at: str | None


def _split_title_and_source(raw_title: str) -> tuple[str, str | None]:
    """Google News titles are "Headline - Outlet Name". Splits the outlet
    off so it can be shown as a byline instead of buried in the headline.

    Uses the LAST " - " so a hyphenated headline (e.g. "Cyclone Update -
    Live: 40 dead") doesn't get cut at the wrong hyphen — outlet names
    never contain " - " themselves, but headlines sometimes do.
    """
    if " - " not in raw_title:
        return raw_title, None
    headline, _, source = raw_title.rpartition(" - ")
    return headline, source


class ClimateNewsProvider:
    def __init__(self, base_url: str = NEWS_BASE_URL, client: httpx.Client | None = None):
        self._base_url = base_url
        self._owns_client = client is None
        self._client = client or httpx.Client(timeout=10.0)

    def close(self) -> None:
        if self._owns_client:
            self._client.close()

    def __enter__(self) -> "ClimateNewsProvider":
        return self

    def __exit__(self, *exc_info) -> None:
        self.close()

    def fetch_headlines(self, limit: int = 30) -> list[NewsItemData]:
        """The current climate/weather-disaster headlines, most recent
        first (Google News' own feed order). Returns an empty list rather
        than raising if the feed is momentarily malformed — a stale or
        empty Discover tab is a better failure than a crashed screen for
        content that is not safety-critical, unlike alerts/weather."""
        response = self._client.get(
            self._base_url,
            params=_QUERY_PARAMS,
            headers={"User-Agent": _USER_AGENT},
        )
        response.raise_for_status()

        try:
            root = ElementTree.fromstring(response.text)
        except ElementTree.ParseError as exc:
            logger.warning("Failed to parse climate news RSS: %s", exc)
            return []

        items = []
        for item in root.findall("./channel/item")[:limit]:
            raw_title = item.findtext("title")
            link = item.findtext("link")
            if not raw_title or not link:
                # A title or link is the minimum for a usable headline;
                # skip rather than surface a blank card.
                continue
            headline, source = _split_title_and_source(raw_title)
            items.append(
                NewsItemData(
                    title=headline,
                    source=source,
                    link=link,
                    published_at=item.findtext("pubDate"),
                )
            )
        return items
