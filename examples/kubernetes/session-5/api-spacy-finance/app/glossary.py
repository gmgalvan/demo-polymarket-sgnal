"""Finance glossary used to answer questions.

We are not using a generative LLM here: the spaCy model (en_core_web_sm)
is only used to tokenize/lemmatize the user's question, and a
PhraseMatcher looks for matches against this glossary. It's deliberately
lightweight so it can run on CPU (e.g. a Graviton/ARM node).

FINANCE_GLOSSARY below is the seed data: on first startup it's written
into MongoDB's `terms` collection (see db.py), and from then on the
glossary served by the API is whatever is in Mongo, not this dict. This
module also stays as the fallback if Mongo is unreachable, so the API
degrades instead of dying.
"""

from spacy.matcher import PhraseMatcher

FINANCE_GLOSSARY = {
    "roi": {
        "name": "ROI (Return on Investment)",
        "patterns": ["roi", "return on investment"],
        "answer": (
            "ROI measures the profitability of an investment: "
            "(Gain - Cost) / Cost, expressed as a percentage."
        ),
    },
    "compound_interest": {
        "name": "Compound interest",
        "patterns": ["compound interest"],
        "answer": (
            "Compound interest is interest calculated on the initial "
            "principal plus the accumulated interest from previous "
            "periods. That's why it grows exponentially over time."
        ),
    },
    "simple_interest": {
        "name": "Simple interest",
        "patterns": ["simple interest"],
        "answer": (
            "Simple interest is calculated only on the initial "
            "principal, without reinvesting the interest earned in "
            "previous periods."
        ),
    },
    "inflation": {
        "name": "Inflation",
        "patterns": ["inflation", "what is inflation"],
        "answer": (
            "Inflation is the widespread and sustained rise in the "
            "prices of goods and services, which reduces the "
            "purchasing power of money."
        ),
    },
    "diversification": {
        "name": "Diversification",
        "patterns": ["diversification", "diversify"],
        "answer": (
            "Diversifying means spreading an investment across "
            "different assets to reduce the overall risk of the "
            "portfolio."
        ),
    },
    "liquidity": {
        "name": "Liquidity",
        "patterns": ["liquidity"],
        "answer": (
            "Liquidity is how easily an asset can be converted into "
            "cash without losing significant value."
        ),
    },
    "leverage": {
        "name": "Financial leverage",
        "patterns": ["leverage", "financial leverage"],
        "answer": (
            "Leverage is the use of debt to increase the size of an "
            "investment, which amplifies both potential gains and "
            "potential losses."
        ),
    },
    "ebitda": {
        "name": "EBITDA",
        "patterns": ["ebitda"],
        "answer": (
            "EBITDA is a company's earnings before interest, taxes, "
            "depreciation, and amortization. It measures operating "
            "profitability without the effect of accounting or "
            "financing decisions."
        ),
    },
    "dividend": {
        "name": "Dividend",
        "patterns": ["dividend", "dividends"],
        "answer": (
            "A dividend is the portion of a company's profits that is "
            "distributed to its shareholders, usually in cash."
        ),
    },
    "bitcoin": {
        "name": "Investing in Bitcoin / crypto",
        "patterns": [
            "bitcoin",
            "btc",
            "invest in bitcoin",
            "invest in cryptocurrency",
            "invest in crypto",
            "should i invest in bitcoin",
        ],
        "answer": (
            "Bitcoin and other cryptocurrencies are extremely volatile "
            "assets: they can rise or fall more than 10% in a single "
            "day, trade 24/7, and their value depends largely on market "
            "expectations and liquidity, not cash flows like a company. "
            "Before investing, consider your time horizon, risk "
            "tolerance, diversify, and don't put in money you'll need "
            "in the short term. This is educational information, not "
            "investment advice."
        ),
    },
    "chart_patterns": {
        "name": "Chart patterns (technical analysis)",
        "patterns": [
            "chart patterns",
            "price patterns",
            "technical patterns",
            "what are chart patterns",
            "trading patterns",
        ],
        "answer": (
            "Chart patterns are recurring formations in an asset's "
            "price chart (like BTC) that traders use to anticipate "
            "possible future moves. Common ones: support and "
            "resistance, head and shoulders, double top/bottom, "
            "triangles, and candlesticks. They're a probability tool, "
            "not a guarantee of outcome."
        ),
    },
    "support_resistance": {
        "name": "Support and resistance",
        "patterns": ["support and resistance", "support", "resistance"],
        "answer": (
            "Support is a price level where demand tends to stop a "
            "decline, and resistance is a level where supply tends to "
            "stop a rise. When price breaks through one of these "
            "levels with volume, it's usually read as a signal of "
            "continuation in that direction."
        ),
    },
    "head_and_shoulders": {
        "name": "Head and shoulders pattern",
        "patterns": ["head and shoulders", "head and shoulders pattern"],
        "answer": (
            "Head and shoulders is a reversal pattern: three peaks "
            "where the middle one (head) is higher than the two side "
            "ones (shoulders). It usually anticipates the end of an "
            "uptrend when price breaks the 'neckline' connecting the "
            "valleys between the peaks."
        ),
    },
    "double_top_bottom": {
        "name": "Double top / double bottom",
        "patterns": [
            "double top",
            "double bottom",
            "double top and double bottom",
        ],
        "answer": (
            "A double top is a bearish reversal pattern: price touches "
            "the same high level twice without breaking above it. A "
            "double bottom is the bullish equivalent: price touches "
            "the same low level twice without breaking below it. Both "
            "signal that the prior trend is losing strength."
        ),
    },
    "triangle": {
        "name": "Triangle (chart pattern)",
        "patterns": [
            "triangle",
            "triangle pattern",
            "ascending triangle",
            "descending triangle",
        ],
        "answer": (
            "A triangle forms when the price range narrows between two "
            "converging trendlines. It usually signals that the market "
            "is undecided and that a strong move is approaching once "
            "either side breaks."
        ),
    },
    "candlestick": {
        "name": "Candlesticks",
        "patterns": [
            "candlestick",
            "candlesticks",
            "japanese candlestick",
            "what is a candlestick",
        ],
        "answer": (
            "A candlestick shows the open, close, high, and low of an "
            "asset over a time period (for example, 5 minutes). "
            "Combinations of several candles form patterns like the "
            "hammer, engulfing, or doji, used to read market sentiment "
            "during that period."
        ),
    },
    "trend": {
        "name": "Uptrend / downtrend",
        "patterns": [
            "uptrend",
            "downtrend",
            "what is a trend",
            "market trend",
        ],
        "answer": (
            "An uptrend is a series of progressively higher highs and "
            "higher lows; a downtrend is a series of progressively "
            "lower highs and lower lows. Identifying the trend is the "
            "foundation of technical analysis before looking for "
            "specific patterns."
        ),
    },
}


def build_matcher(nlp, glossary: dict) -> PhraseMatcher:
    """Builds a lemma-based PhraseMatcher from a glossary dict."""
    matcher = PhraseMatcher(nlp.vocab, attr="LEMMA")
    for key, data in glossary.items():
        patterns = [nlp(p) for p in data["patterns"]]
        matcher.add(key, patterns)
    return matcher


def seed_terms(collection) -> None:
    """Writes FINANCE_GLOSSARY into Mongo if the collection is empty.

    Uses the glossary key as _id, so re-running this is a no-op once
    the collection has data - it never overwrites edits made directly
    in Mongo.
    """
    if collection.estimated_document_count() > 0:
        return
    docs = [{"_id": key, **data} for key, data in FINANCE_GLOSSARY.items()]
    collection.insert_many(docs)


def load_glossary_from_db(collection) -> dict:
    """Reads the glossary out of Mongo, shaped like FINANCE_GLOSSARY."""
    return {
        doc["_id"]: {
            "name": doc["name"],
            "patterns": doc["patterns"],
            "answer": doc["answer"],
        }
        for doc in collection.find()
    }
