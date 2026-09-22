from fastapi import APIRouter, Depends

from app.auth import require_token

API_VERSION = 1

router = APIRouter(prefix="/api")


@router.get("/health")
def health() -> dict:
    return {"status": "ok", "api_version": API_VERSION}


@router.get("/auth/check", dependencies=[Depends(require_token)])
def auth_check() -> dict:
    """Lets clients verify the server URL and token from their settings screen."""
    return {"ok": True}
