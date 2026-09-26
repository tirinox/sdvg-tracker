import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.emoji.encoder import MODEL_FILE, Encoder
from app.emoji.suggest import EmojiSuggester, Suggestion, load_descriptions
from app.main import create_app
from tests.conftest import AUTH, TEST_TOKEN

MODEL_DIR = Path(__file__).resolve().parents[1] / "models" / "multilingual-e5-small"
needs_model = pytest.mark.skipif(
    not (MODEL_DIR / MODEL_FILE).exists(), reason="no emoji model: make emoji-model"
)


# Catalog and task phrases


def test_descriptions_are_grouped_by_emoji():
    emoji, owners, texts = load_descriptions()
    assert len(emoji) == len(set(emoji)) > 1000
    assert len(owners) == len(texts) > len(emoji)
    assert owners == sorted(owners)
    assert set(owners) == set(range(len(emoji)))


def test_catalog_leaves_out_noise():
    emoji, _, _ = load_descriptions()
    for char in emoji:
        assert "⃣" not in char, "keycap"
        assert not any(0x1F550 <= ord(c) <= 0x1F567 for c in char), "clock face"
        assert not any(0x1F3FB <= ord(c) <= 0x1F3FF for c in char), "skin tone"
        assert not ("‍" in char and ("♀" in char or "♂" in char)), "gendered duplicate"
    assert {"🦷", "🛒", "🇬🇧", "🧑‍💻"} <= set(emoji)
    assert "🇩🇬" not in emoji


# API, with a stand-in for the model


class FakeSuggester:
    ready = True
    failed = False

    def __init__(self):
        self.calls = []

    def suggest(self, text, limit):
        self.calls.append((text, limit))
        return [Suggestion("🐕", 0.95), Suggestion("🚶", 0.9)][:limit]


def suggest(client, **body):
    return client.post("/api/suggest-emoji", json=body, headers=AUTH)


def test_requires_token(client):
    assert client.post("/api/suggest-emoji", json={"text": "Выгулять собаку"}).status_code == 401


def test_unavailable_without_model(client):
    resp = suggest(client, text="Выгулять собаку")
    assert resp.status_code == 503
    assert resp.json()["detail"] == {"error": "emoji_unavailable"}


def test_loading(client):
    client.app.state.emoji = FakeSuggester()
    client.app.state.emoji.ready = False
    resp = suggest(client, text="Выгулять собаку")
    assert resp.status_code == 503
    assert resp.json()["detail"] == {"error": "emoji_loading"}
    assert resp.headers["Retry-After"] == "10"


def test_suggests(client):
    client.app.state.emoji = fake = FakeSuggester()
    resp = suggest(client, text="  Выгулять собаку ", limit=2)
    assert resp.status_code == 200
    assert resp.json() == {
        "suggestions": [{"emoji": "🐕", "score": 0.95}, {"emoji": "🚶", "score": 0.9}]
    }
    assert fake.calls == [("Выгулять собаку", 2)]
    suggest(client, text="Выгулять собаку")
    assert fake.calls[-1] == ("Выгулять собаку", 5)


@pytest.mark.parametrize(
    "body",
    [
        {"text": ""},
        {"text": "   "},
        {"text": "a" * 501},
        {"text": "Спорт", "limit": 0},
        {"text": "Спорт", "limit": 21},
        {"text": "Спорт", "lang": "ru"},
        {},
    ],
)
def test_rejects_bad_requests(client, body):
    client.app.state.emoji = FakeSuggester()
    assert suggest(client, **body).status_code == 422


# The real model


@pytest.fixture(scope="module")
def cache_dir(tmp_path_factory):
    return tmp_path_factory.mktemp("emoji-cache")


@pytest.fixture(scope="module")
def suggester(cache_dir):
    s = EmojiSuggester(MODEL_DIR, cache_dir, threads=4)
    s.load()
    assert s.ready
    return s


@needs_model
def test_token_ids_match_the_reference_tokenizer():
    # Ids from the model's own tokenizer.json (HF tokenizers).
    encoder = Encoder(MODEL_DIR)
    assert encoder.ids("query: Записаться к стоматологу") == [
        0, 41, 1294, 12, 829, 149330, 989, 718, 196530, 105, 2,
    ]  # fmt: skip
    assert encoder.ids("query: Выгулять собаку 🐕") == [
        0, 41, 1294, 12, 3499, 99427, 1117, 59095, 105, 6, 3, 2,
    ]  # fmt: skip


@needs_model
@pytest.mark.parametrize(
    ("title", "acceptable"),
    [
        ("Выгулять собаку", "🐕 🐶 🦮"),
        ("Принять таблетки", "💊"),
        ("Записаться к стоматологу", "🦷"),
        ("Вынести мусор", "🗑️ 🚮"),
        ("Купить продукты", "🛒 🛍️"),
        ("Позвонить маме", "📞 ☎️ 📱"),
        ("Оплатить интернет", "💳 🛜 🌐"),
        ("Пробежка", "🏃"),
        ("Английский 15 минут", "🇬🇧"),
        ("Лечь спать вовремя", "😴 🛌"),
        ("Помыть посуду", "🧽 🍽️"),
        ("Walk the dog", "🐕 🐶 🦮"),
    ],
)
def test_suggests_a_fitting_emoji(suggester, title, acceptable):
    top = [s.emoji for s in suggester.suggest(title, 3)]
    assert set(acceptable.split()) & set(top), f"{title}: {top}"


def plain(emoji: str) -> str:
    """Without the emoji presentation selector: 👁 and 👁️ are the same answer."""
    return emoji.replace("\ufe0f", "")


@needs_model
def test_pass_rate_on_task_titles(suggester):
    """First suggestion fits 74% of emoji_titles.txt, one of the top three 90% (at writing)."""
    first = top3 = total = 0
    for line in (Path(__file__).parent / "emoji_titles.txt").read_text().splitlines():
        if line.strip() and not line.startswith("#"):
            title, acceptable = line.split("|")
            fits = {plain(e) for e in acceptable.split()}
            top = [plain(s.emoji) for s in suggester.suggest(title.strip(), 3)]
            first += top[0] in fits
            top3 += bool(fits & set(top))
            total += 1
    assert total == 50
    assert first / total >= 0.7
    assert top3 / total >= 0.85


@needs_model
def test_scores_are_ranked(suggester):
    scores = [s.score for s in suggester.suggest("Сходить в спортзал", 10)]
    assert len(scores) == 10
    assert scores == sorted(scores, reverse=True)


@needs_model
def test_vectors_are_cached(suggester, cache_dir, monkeypatch):
    assert len(list(cache_dir.glob("emoji-vectors-*.npy"))) == 1
    encode = Encoder.encode

    def encode_one(self, texts, *args):
        assert len(texts) == 1, "descriptions re-encoded instead of read from the cache"
        return encode(self, texts, *args)

    monkeypatch.setattr(Encoder, "encode", encode_one)
    again = EmojiSuggester(MODEL_DIR, cache_dir)
    again.load()
    assert again.ready
    assert again.suggest("Выгулять собаку", 3) == suggester.suggest("Выгулять собаку", 3)


@needs_model
def test_unreadable_cache_is_rebuilt(suggester, cache_dir, tmp_path):
    [cached] = cache_dir.glob("emoji-vectors-*.npy")
    (tmp_path / cached.name).write_bytes(b"not a numpy file")
    again = EmojiSuggester(MODEL_DIR, tmp_path, threads=4)
    again.load()
    assert again.ready
    assert (tmp_path / cached.name).read_bytes() == cached.read_bytes()


@needs_model
def test_api_with_the_model(suggester, cache_dir, tmp_path):
    settings = Settings(
        api_token=TEST_TOKEN,
        database_path=str(tmp_path / "test.db"),
        emoji_model_dir=MODEL_DIR,
        emoji_cache_dir=cache_dir,
    )
    with TestClient(create_app(settings)) as client:
        deadline = time.monotonic() + 60
        while (resp := suggest(client, text="Выгулять собаку")).status_code == 503:
            assert resp.json()["detail"]["error"] == "emoji_loading"
            assert time.monotonic() < deadline
            time.sleep(0.1)
        assert resp.status_code == 200
        assert resp.json()["suggestions"][0]["emoji"] == "🐕"
