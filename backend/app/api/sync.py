from fastapi import APIRouter, Depends, HTTPException, Request, status

from app.auth import require_token
from app.sync.schemas import SyncRequest, SyncResponse
from app.sync.service import SyncError, sync

router = APIRouter(prefix="/api", dependencies=[Depends(require_token)])


@router.post("/sync")
def post_sync(req: SyncRequest, request: Request) -> SyncResponse:
    try:
        return sync(request.app.state.engine, request.app.state.validator, req)
    except SyncError as e:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail={"message": str(e), "change_index": e.index},
        ) from e
