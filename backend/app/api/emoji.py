from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

from app.auth import require_token
from app.emoji.suggest import CONFIDENT

router = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


class SuggestEmojiRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    # In the body, not the URL: titles are private and URLs end up in access logs.
    text: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
    limit: int = Field(default=5, ge=1, le=20)


class EmojiSuggestion(BaseModel):
    emoji: str
    # Cosine similarity to the closest description; comparable only within one response.
    score: float


class SuggestEmojiResponse(BaseModel):
    suggestions: list[EmojiSuggestion]
    # The emoji a client may set without asking (the first suggestion, if the model is sure
    # enough), or null: then it only offers the suggestions.
    pick: str | None


@router.post("/suggest-emoji")
def suggest_emoji(req: SuggestEmojiRequest, request: Request) -> SuggestEmojiResponse:
    """Emoji for a task title, best first. 503 while the model loads or if it isn't installed."""
    suggester = request.app.state.emoji
    if suggester is None or not suggester.ready:
        reason = "loading" if suggester and not suggester.failed else "unavailable"
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"error": f"emoji_{reason}"},
            headers={"Retry-After": "10"} if reason == "loading" else None,
        )
    suggestions = suggester.suggest(req.text, req.limit)
    first = suggestions[0] if suggestions else None
    return SuggestEmojiResponse(
        suggestions=[EmojiSuggestion(emoji=s.emoji, score=s.score) for s in suggestions],
        pick=first.emoji if first and first.score >= CONFIDENT else None,
    )
