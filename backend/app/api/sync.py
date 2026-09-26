from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.auth import require_token
from app.sync.schemas import SyncInfo, SyncRequest, SyncResponse
from app.sync.service import ServerChanged, SyncError, info, sync

router = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


@router.post("/sync")
def post_sync(req: SyncRequest, request: Request) -> SyncResponse:
    try:
        return sync(request.app.state.engine, request.app.state.validator, req)
    except ServerChanged as e:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"error": "server_changed", **e.info.model_dump()},
        ) from e
    except SyncError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={"message": str(e), "change_index": e.index},
        ) from e


@router.get("/sync/info")
def get_sync_info(request: Request) -> SyncInfo:
    """Which database this is and how many rows it holds, without pushing anything."""
    return info(request.app.state.engine)
