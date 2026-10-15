import logging
import logging.config
from contextlib import asynccontextmanager

import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.database import close_connection_pool, init_connection_pool

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up…")
    init_connection_pool()
    yield
    logger.info("Shutting down…")
    close_connection_pool()

app = FastAPI(
    title="test run",
    version="1.0.0",
    description="database concept",
    lifespan=lifespan,
)

from app.core.middleware import setup_middlewares
setup_middlewares(app)

from app.routers.router import router as api_router
app.include_router(api_router)