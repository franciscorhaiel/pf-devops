"""API de ejemplo para el proyecto final de infraestructura cloud.

Expone endpoints de negocio, health checks para Kubernetes y metricas
en formato Prometheus.
"""
import os
import time

from fastapi import FastAPI, HTTPException, status
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
ARRANQUE = time.time()

app = FastAPI(
    title="PF Cloud API",
    version=APP_VERSION,
    description="API de demostracion del pipeline CI/CD sobre Kubernetes.",
)

# Expone /metrics para que Prometheus lo scrapee.
Instrumentator().instrument(app).expose(app, endpoint="/metrics")


class Tarea(BaseModel):
    id: int
    titulo: str = Field(min_length=1, max_length=120)
    completada: bool = False


_tareas: dict[int, Tarea] = {}
_proximo_id = 1


@app.get("/")
def raiz():
    return {"servicio": "pf-cloud-api", "version": APP_VERSION}


@app.get("/healthz", status_code=status.HTTP_200_OK)
def liveness():
    """Liveness probe: el proceso esta vivo."""
    return {"status": "ok"}


@app.get("/readyz", status_code=status.HTTP_200_OK)
def readiness():
    """Readiness probe: la app puede recibir trafico."""
    return {"status": "ready", "uptime_seg": round(time.time() - ARRANQUE, 2)}


@app.get("/tareas")
def listar_tareas() -> list[Tarea]:
    return list(_tareas.values())


@app.post("/tareas", status_code=status.HTTP_201_CREATED)
def crear_tarea(titulo: str) -> Tarea:
    global _proximo_id
    if not titulo.strip():
        raise HTTPException(status_code=422, detail="El titulo no puede estar vacio")
    tarea = Tarea(id=_proximo_id, titulo=titulo.strip())
    _tareas[_proximo_id] = tarea
    _proximo_id += 1
    return tarea


@app.get("/tareas/{tarea_id}")
def obtener_tarea(tarea_id: int) -> Tarea:
    if tarea_id not in _tareas:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
    return _tareas[tarea_id]


@app.get("/carga")
def generar_carga(iteraciones: int = 100_000):
    """Endpoint de CPU intensiva, usado para disparar el HPA en la demo."""
    iteraciones = min(iteraciones, 5_000_000)
    total = sum(i * i % 7 for i in range(iteraciones))
    return {"iteraciones": iteraciones, "resultado": total}
