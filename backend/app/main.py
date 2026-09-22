from fastapi import FastAPI

from app.api import system


def create_app() -> FastAPI:
    app = FastAPI(title="SDVG Tracker")
    app.include_router(system.router)
    return app


app = create_app()
