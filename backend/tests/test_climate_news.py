"""ClimateNewsProvider: parses Google News' RSS feed into headline items.
"""

import httpx

from app.providers.climate_news import ClimateNewsProvider

SAMPLE_RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
<title>Climate News - Google News</title>
<item>
<title>Cyclone hits eastern coast - The Hindu</title>
<link>https://news.google.com/articles/abc</link>
<pubDate>Thu, 10 Sep 2026 12:00:00 GMT</pubDate>
</item>
<item>
<title>Record heatwave grips Europe - BBC News</title>
<link>https://news.google.com/articles/def</link>
<pubDate>Thu, 10 Sep 2026 10:00:00 GMT</pubDate>
</item>
<item>
<title>Headline with a hyphen - in it - Reuters</title>
<link>https://news.google.com/articles/ghi</link>
<pubDate>Thu, 10 Sep 2026 09:00:00 GMT</pubDate>
</item>
<item>
<title>No source separator here</title>
<link>https://news.google.com/articles/jkl</link>
<pubDate>Thu, 10 Sep 2026 08:00:00 GMT</pubDate>
</item>
</channel>
</rss>"""


def _provider_returning(text):
    def handler(request):
        return httpx.Response(200, text=text)

    return ClimateNewsProvider(
        client=httpx.Client(transport=httpx.MockTransport(handler))
    )


def test_fetch_headlines_parses_title_source_and_link():
    items = _provider_returning(SAMPLE_RSS).fetch_headlines()

    assert len(items) == 4
    assert items[0].title == "Cyclone hits eastern coast"
    assert items[0].source == "The Hindu"
    assert items[0].link == "https://news.google.com/articles/abc"
    assert items[0].published_at == "Thu, 10 Sep 2026 12:00:00 GMT"


def test_fetch_headlines_splits_on_the_last_hyphen_only():
    items = _provider_returning(SAMPLE_RSS).fetch_headlines()

    hyphenated = items[2]
    assert hyphenated.title == "Headline with a hyphen - in it"
    assert hyphenated.source == "Reuters"


def test_fetch_headlines_leaves_source_none_without_a_separator():
    items = _provider_returning(SAMPLE_RSS).fetch_headlines()

    assert items[3].title == "No source separator here"
    assert items[3].source is None


def test_fetch_headlines_respects_limit():
    items = _provider_returning(SAMPLE_RSS).fetch_headlines(limit=2)

    assert len(items) == 2


def test_fetch_headlines_returns_empty_list_on_malformed_xml():
    items = _provider_returning("not xml at all").fetch_headlines()

    assert items == []


def test_fetch_headlines_can_be_called_on_a_provider_used_as_context_manager():
    with _provider_returning(SAMPLE_RSS) as provider:
        items = provider.fetch_headlines()

    assert len(items) == 4
