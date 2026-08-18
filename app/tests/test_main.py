from fastapi.testclient import TestClient

from app.main import app

cliente = TestClient(app)


def test_raiz_devuelve_version():
    r = cliente.get("/")
    assert r.status_code == 200
    assert r.json()["servicio"] == "pf-cloud-api"


def test_liveness():
    assert cliente.get("/healthz").status_code == 200


def test_readiness_incluye_uptime():
    r = cliente.get("/readyz")
    assert r.status_code == 200
    assert "uptime_seg" in r.json()


def test_metrics_expone_formato_prometheus():
    r = cliente.get("/metrics")
    assert r.status_code == 200
    assert "http_request" in r.text


def test_crear_y_obtener_tarea():
    r = cliente.post("/tareas", params={"titulo": "Desplegar en k8s"})
    assert r.status_code == 201
    tid = r.json()["id"]
    assert cliente.get(f"/tareas/{tid}").json()["titulo"] == "Desplegar en k8s"


def test_tarea_inexistente_devuelve_404():
    assert cliente.get("/tareas/99999").status_code == 404


def test_titulo_vacio_rechazado():
    assert cliente.post("/tareas", params={"titulo": "   "}).status_code == 422


def test_endpoint_carga_limita_iteraciones():
    r = cliente.get("/carga", params={"iteraciones": 99_000_000})
    assert r.json()["iteraciones"] == 5_000_000
