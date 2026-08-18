# PF Cloud — Pipeline CI/CD completo sobre Kubernetes

Proyecto final de infraestructura cloud y automatización. Implementa un pipeline
de punta a punta: una API en FastAPI empaquetada con Docker multi-stage,
infraestructura declarada en Terraform, despliegue automatizado en Kubernetes
con auto-escalado, monitoreo con Prometheus y Grafana, y controles de FinOps.

Todo el entorno corre **localmente sobre kind**, sin costo de cloud, pero usando
Terraform y Kubernetes reales (no simulados).

---

## Índice

1. [Arquitectura](#arquitectura)
2. [Estructura del repositorio](#estructura-del-repositorio)
3. [Requisitos previos](#requisitos-previos)
4. [Ejecución local paso a paso](#ejecución-local-paso-a-paso)
5. [Despliegue con Terraform](#despliegue-con-terraform)
6. [Pipeline CI/CD](#pipeline-cicd)
7. [Cómo validar el despliegue](#cómo-validar-el-despliegue)
8. [Monitoreo](#monitoreo)
9. [Auto-escalado (HPA)](#auto-escalado-hpa)
10. [FinOps](#finops)
11. [Seguridad](#seguridad)
12. [Evidencias](#evidencias)
13. [Troubleshooting](#troubleshooting)

---

## Arquitectura

```
                         ┌──────────────────────────┐
   git push ────────────►│   GitHub Actions (CI)    │
                         │  lint → test → SAST      │
                         │  build multi-stage       │
                         │  Trivy → push a GHCR     │
                         │  DAST (OWASP ZAP)        │
                         └───────────┬──────────────┘
                                     │ imagen:sha
                         ┌───────────▼──────────────┐
                         │   GitHub Actions (CD)    │
                         │  terraform fmt/validate  │
                         │  kind + ingress + HPA    │
                         │  kubectl apply -k        │
                         │  smoke tests             │
                         └───────────┬──────────────┘
                                     │
    ┌────────────────────────────────▼─────────────────────────────────┐
    │                     Cluster Kubernetes (kind)                    │
    │                                                                  │
    │   Internet                                                       │
    │      │                                                           │
    │      ▼                                                           │
    │  ┌────────┐    ┌─────────┐    ┌─────────────────────┐            │
    │  │Ingress │───►│ Service │───►│ Deployment (2–10)   │            │
    │  │ nginx  │    │ClusterIP│    │  Pod: api :8000     │            │
    │  └────────┘    └─────────┘    │  non-root, RO fs    │            │
    │                               └──────┬──────────────┘            │
    │                                      │ /metrics                  │
    │                        ┌─────────────▼────────────┐              │
    │   ┌──────┐             │  HPA (CPU 70% / RAM 80%) │              │
    │   │Grafana│◄───────────┤  metrics-server          │              │
    │   └──────┘   ┌─────────▼──────────┐               │              │
    │              │    Prometheus      │◄──────────────┘              │
    │              │  + PrometheusRule  │                              │
    │              └────────────────────┘                              │
    │                                                                  │
    │   namespace pf-app: ResourceQuota + LimitRange + NetworkPolicy   │
    └──────────────────────────────────────────────────────────────────┘
```

**Flujo de una request:** `Ingress (nginx)` recibe en el puerto 80, resuelve por
host `pf-cloud.local`, enruta al `Service` ClusterIP, que balancea entre los
Pods del `Deployment`. El HPA observa las métricas de CPU y memoria vía
`metrics-server` y ajusta el número de réplicas entre 2 y 10.

---

## Estructura del repositorio

```
.
├── app/                          Aplicación FastAPI
│   ├── main.py                   Endpoints, health checks, /metrics
│   ├── requirements.txt          Dependencias de producción (pinneadas)
│   ├── requirements-dev.txt      Dependencias de test y linters
│   └── tests/test_main.py        8 tests unitarios
│
├── Dockerfile                    Multi-stage de 3 etapas
├── .dockerignore                 Reduce contexto y evita filtrar secretos
│
├── terraform/
│   ├── main.tf                   Composición de módulos + Helm
│   ├── variables.tf              9 variables con validaciones
│   ├── outputs.tf                Incluye estimación de costo FinOps
│   ├── versions.tf               Versiones fijadas de providers
│   ├── example.tfvars            Plantilla (terraform.tfvars va en .gitignore)
│   └── modules/
│       ├── kind_cluster/         Provisiona el cluster
│       └── k8s_app/              Namespace, Quota, Deployment, Service, HPA, PDB
│
├── k8s/                          Manifiestos declarativos
│   ├── 00-namespace.yaml
│   ├── 10-deployment.yaml        Probes, securityContext, resources
│   ├── 20-service.yaml
│   ├── 30-ingress.yaml
│   ├── 40-hpa.yaml               Con behavior de scale-up/down
│   ├── 50-pdb.yaml
│   ├── 60-networkpolicy.yaml
│   └── kustomization.yaml
│
├── monitoring/
│   ├── values-prometheus.yaml    kube-prometheus-stack acotado
│   ├── servicemonitor.yaml       Scrapeo de la app
│   ├── alertas.yaml              Alertas de disponibilidad + FinOps
│   └── grafana-dashboard.json    6 paneles
│
├── finops/
│   ├── README.md                 Las 7 medidas, con cálculo de ahorro
│   └── kube-downscaler.yaml      Apagado fuera de horario
│
├── scripts/
│   ├── kind-config.yaml
│   ├── setup.sh                  Levanta todo de cero (idempotente)
│   ├── load-test.sh              Genera carga y captura el escalado
│   └── teardown.sh               Destruye todo
│
├── .github/workflows/
│   ├── ci.yml                    Lint, test, SAST, build, Trivy, DAST
│   └── cd.yml                    Terraform, deploy, smoke tests
│
├── .zap/rules.tsv                Falsos positivos de ZAP
└── docs/                         Informe y evidencias
```

---

## Requisitos previos

| Herramienta | Versión mínima | Verificar con |
|---|---|---|
| Docker | 24.0 | `docker --version` |
| kind | 0.24 | `kind --version` |
| kubectl | 1.30 | `kubectl version --client` |
| Helm | 3.15 | `helm version` |
| kustomize | 5.4 | `kustomize version` |
| Terraform | 1.6 | `terraform version` |

Instalación en macOS:

```bash
brew install docker kind kubectl helm kustomize terraform
```

Recursos recomendados para Docker Desktop: **4 CPU y 8 GB de RAM**. Con menos,
el stack de monitoreo puede no arrancar.

---

## Ejecución local paso a paso

### Opción rápida: un solo comando

```bash
git clone <URL-DEL-REPO> && cd pf-devops
./scripts/setup.sh
```

El script hace los 7 pasos, es idempotente y tarda entre 8 y 12 minutos la
primera vez (la mayor parte es descargar el chart de Prometheus).

### Opción manual: paso por paso

**1. Correr los tests fuera de Docker**

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r app/requirements-dev.txt
pytest app/tests -v
ruff check app
bandit -r app -x app/tests
```

**2. Levantar la app sin Kubernetes**

```bash
uvicorn app.main:app --reload --port 8000
curl http://localhost:8000/healthz          # {"status":"ok"}
curl http://localhost:8000/metrics | head   # formato Prometheus
open http://localhost:8000/docs             # Swagger UI
```

**3. Construir la imagen y comparar tamaños**

```bash
docker build --target builder -t pf-cloud-api:builder .
docker build --target runtime  -t pf-cloud-api:1.0.0  .
docker images | grep pf-cloud-api
```

La etapa `builder` incluye `build-essential` y `gcc`; la `runtime` no. Esa
diferencia es la evidencia del multi-stage y va en el informe.

**4. Verificar que el contenedor no corre como root**

```bash
docker run --rm pf-cloud-api:1.0.0 id
# uid=10001(appuser) gid=10001(appgroup)
```

**5. Crear el cluster**

```bash
kind create cluster --config scripts/kind-config.yaml
kubectl cluster-info --context kind-pf-cloud
kubectl get nodes
```

**6. Instalar ingress-nginx y metrics-server**

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=300s

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

> El patch de `--kubelet-insecure-tls` es necesario en kind porque los
> certificados de kubelet son autofirmados. Sin esto el HPA muestra `<unknown>`
> permanentemente.

**7. Cargar la imagen y desplegar**

```bash
kind load docker-image pf-cloud-api:1.0.0 --name pf-cloud
cd k8s && kustomize edit set image ghcr.io/USUARIO/pf-cloud-api=pf-cloud-api:1.0.0 && cd ..
kubectl apply -k k8s/
kubectl -n pf-app rollout status deployment/pf-cloud-api
```

**8. Acceder por el Ingress**

```bash
echo "127.0.0.1 pf-cloud.local" | sudo tee -a /etc/hosts
curl http://pf-cloud.local/healthz
```

---

## Despliegue con Terraform

Terraform provisiona el cluster **y** la aplicación, en dos módulos separados.

```bash
cd terraform
cp example.tfvars terraform.tfvars   # editar según necesidad
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Salida esperada:

```
cluster_name      = "pf-cloud"
namespace_app     = "pf-app"
service_app       = "pf-cloud-api"
finops_estimacion = {
  costo_minimo_mes_usd = 5.12
  costo_maximo_mes_usd = 25.6
  memoria_request_mb   = 128
  replicas_minimas     = 2
  replicas_maximas     = 10
}
```

Para destruir:

```bash
terraform destroy
```

### Por qué dos módulos

`kind_cluster` produce la infraestructura; `k8s_app` consume su kubeconfig y
despliega la carga. La separación permite reemplazar `kind_cluster` por un
módulo de EKS o GKE **sin tocar `k8s_app`**, que es el punto de tener módulos.

---

## Pipeline CI/CD

### CI (`.github/workflows/ci.yml`)

| Job | Qué hace | Herramientas |
|---|---|---|
| `test` | Lint y tests unitarios | ruff, pytest |
| `sast` | Análisis estático de código, secretos e IaC | Bandit, Semgrep, Gitleaks, Checkov |
| `build` | Build multi-stage, escaneo de CVEs, push a GHCR | Buildx, Trivy |
| `dast` | Análisis dinámico contra la app corriendo | OWASP ZAP Baseline |

Detalle importante: el job `build` compila **primero la etapa `tester`**. Como
esa etapa ejecuta `pytest`, `bandit` y `ruff` dentro del `RUN`, si algo falla el
build se corta y la imagen nunca se publica. Los tests son parte del build, no
un paso paralelo que se pueda saltear.

Los resultados de Bandit, Checkov y Trivy se suben en formato SARIF, así que
aparecen en la pestaña **Security → Code scanning** del repositorio.

### CD (`.github/workflows/cd.yml`)

Se dispara automáticamente cuando CI termina con éxito en `main`, o a mano con
`workflow_dispatch`.

1. `terraform fmt -check`, `init`, `validate`, `plan` (el plan se guarda como artifact)
2. Crea un cluster kind efímero en el runner
3. Instala ingress-nginx y metrics-server
4. Construye la imagen y la carga con `kind load`
5. Aplica los manifiestos con `kustomize`
6. Espera el `rollout status`
7. Smoke tests contra `/healthz`, `/readyz` y `/metrics`
8. Verifica que el HPA esté leyendo métricas (no `<unknown>`)
9. Si algo falla, imprime `describe pods`, logs y eventos

### Secretos necesarios

| Secreto | Para qué | Notas |
|---|---|---|
| `GITHUB_TOKEN` | Push a GHCR | Automático, no hay que crearlo |
| `SEMGREP_APP_TOKEN` | Semgrep (opcional) | Solo si se quiere el dashboard |
| `KUBE_CONFIG` | Deploy a cluster real | Solo si se apunta a un cluster externo |

Ninguna credencial está en el código. Todo va por `secrets.*` o por variables
de entorno.

---

## Cómo validar el despliegue

### Checklist de validación

```bash
# 1. Los pods están corriendo y listos
kubectl -n pf-app get pods
# READY 1/1, STATUS Running

# 2. El Service tiene endpoints
kubectl -n pf-app get endpoints pf-cloud-api
# Debe listar las IPs de los pods, no <none>

# 3. El Ingress tiene dirección asignada
kubectl -n pf-app get ingress
# ADDRESS debe estar poblado

# 4. El HPA lee métricas
kubectl -n pf-app get hpa
# TARGETS debe mostrar porcentajes, NO <unknown>

# 5. La app responde por el Ingress
curl -i http://pf-cloud.local/healthz

# 6. Las métricas se exponen
curl -s http://pf-cloud.local/metrics | grep http_request

# 7. El contenedor no corre como root
kubectl -n pf-app exec deploy/pf-cloud-api -- id
# uid=10001

# 8. El filesystem es de solo lectura
kubectl -n pf-app exec deploy/pf-cloud-api -- touch /probe 2>&1
# Read-only file system

# 9. La cuota del namespace está activa
kubectl -n pf-app describe resourcequota

# 10. Un rolling update no genera downtime
kubectl -n pf-app set image deploy/pf-cloud-api api=pf-cloud-api:1.0.0 --record
kubectl -n pf-app rollout status deploy/pf-cloud-api
```

### Prueba de resiliencia

```bash
# Matar un pod y comprobar que se recrea solo
kubectl -n pf-app delete pod -l app.kubernetes.io/name=pf-cloud-api --wait=false
watch kubectl -n pf-app get pods
```

---

## Monitoreo

### Acceso a Grafana

```bash
kubectl -n monitoring port-forward svc/monitoreo-grafana 3000:80
# http://localhost:3000
# usuario: admin
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.password}' | base64 -d
```

El dashboard **PF Cloud - API y FinOps** se provisiona automáticamente desde
`monitoring/grafana-dashboard.json` vía ConfigMap. Seis paneles:

| Panel | Métrica | Para qué sirve |
|---|---|---|
| Requests por segundo | `rate(http_requests_total[5m])` | Tráfico |
| Latencia p95 | `histogram_quantile(0.95, ...)` | Experiencia de usuario |
| Tasa de errores 5xx | ratio de 5xx sobre total | Salud de la app |
| Réplicas del HPA | `kube_horizontalpodautoscaler_status_current_replicas` | Ver el escalado en vivo |
| CPU: uso vs requests | `container_cpu_usage_seconds_total` | **FinOps**: detectar sobreaprovisionamiento |
| Memoria: uso vs limits | `container_memory_working_set_bytes` | **FinOps**: ajustar requests |

### Acceso a Prometheus

```bash
kubectl -n monitoring port-forward svc/monitoreo-kube-prometheus-prometheus 9090:9090
# http://localhost:9090
```

Verificar que la app está siendo scrapeada: **Status → Targets**, buscar el
target `pf-app/pf-cloud-api`. Debe estar en estado `UP`.

### Alertas configuradas

Cuatro de disponibilidad (`AppCaida`, `TasaDeErrores5xx`, `LatenciaAlta`) y dos
de FinOps (`RecursosSobreaprovisionados`, `HPAEnElMaximo`). Ver
`monitoring/alertas.yaml`.

---

## Auto-escalado (HPA)

### Configuración

| Parámetro | Valor | Razón |
|---|---|---|
| `minReplicas` | 2 | Alta disponibilidad mínima |
| `maxReplicas` | 10 | Techo de gasto |
| CPU objetivo | 70% | Margen antes de saturar |
| Memoria objetivo | 80% | La app es más sensible a CPU |
| `scaleUp` window | 30 s | Reaccionar rápido a picos |
| `scaleDown` window | 300 s | Bajar despacio: evita flapping |

El `behavior` asimétrico es deliberado: escalar hacia arriba rápido protege la
experiencia de usuario; escalar hacia abajo despacio evita el ciclo de
crear/destruir pods, que cuesta dinero en arranques y degrada la latencia.

### Probar el escalado

```bash
./scripts/load-test.sh
```

Genera 300 segundos de carga con 30 clientes concurrentes contra `/carga`, y
registra el estado del HPA cada 10 segundos en
`evidencias/hpa-escalado.log`.

Comportamiento esperado:

```
NAME           REFERENCE                 TARGETS           MINPODS  MAXPODS  REPLICAS
pf-cloud-api   Deployment/pf-cloud-api   cpu: 8%/70%       2        10       2
pf-cloud-api   Deployment/pf-cloud-api   cpu: 142%/70%     2        10       2
pf-cloud-api   Deployment/pf-cloud-api   cpu: 142%/70%     2        10       4
pf-cloud-api   Deployment/pf-cloud-api   cpu: 96%/70%      2        10       6
pf-cloud-api   Deployment/pf-cloud-api   cpu: 61%/70%      2        10       6
...
pf-cloud-api   Deployment/pf-cloud-api   cpu: 5%/70%       2        10       2
```

Ese log es una de las evidencias centrales del informe.

---

## FinOps

Siete medidas implementadas. El detalle completo, con el cálculo de ahorro,
está en [`finops/README.md`](finops/README.md).

| Medida | Implementación |
|---|---|
| Imagen mínima multi-stage | `Dockerfile` |
| Requests y limits ajustados | `k8s/10-deployment.yaml` |
| Auto-escalado horizontal | `k8s/40-hpa.yaml` |
| Scale-down conservador | `behavior.scaleDown` |
| ResourceQuota y LimitRange | `terraform/modules/k8s_app` |
| Apagado fuera de horario | `finops/kube-downscaler.yaml` |
| Alertas de sobreaprovisionamiento | `monitoring/alertas.yaml` |

Estimación con los valores por defecto: **USD 5.12/mes** en el piso contra
**USD 25.60/mes** en el techo. Sin HPA habría que aprovisionar para el pico de
forma permanente. Con una carga que pica 4 horas al día, el ahorro estimado es
del **69%**.

Verificar el cálculo:

```bash
cd terraform && terraform output finops_estimacion
```

Y no olvidar la medida más importante:

```bash
./scripts/teardown.sh   # destruir cuando no se usa
```

---

## Seguridad

| Control | Dónde | Qué previene |
|---|---|---|
| Usuario no root (uid 10001) | `Dockerfile`, `securityContext` | Escalada de privilegios |
| `readOnlyRootFilesystem` | `securityContext` | Escritura de payloads |
| `allowPrivilegeEscalation: false` | `securityContext` | setuid |
| `capabilities: drop ALL` | `securityContext` | Syscalls privilegiadas |
| `seccompProfile: RuntimeDefault` | `securityContext` | Superficie de syscalls |
| NetworkPolicy restrictiva | `k8s/60-networkpolicy.yaml` | Movimiento lateral |
| Dependencias pinneadas | `requirements.txt` | Supply chain |
| SBOM y provenance | `docker/build-push-action` | Trazabilidad |
| Rate limiting | Anotaciones del Ingress | Abuso y DoS |
| Secretos por `secrets.*` | Workflows | Credenciales en el repo |
| `.dockerignore` y `.gitignore` | Raíz | Filtrado de `.env`, `.tfstate`, claves |

Escaneos automáticos: Bandit y Semgrep (código), Gitleaks (secretos), Checkov
(IaC), Trivy (imagen), OWASP ZAP (runtime).

---

## Evidencias

Las evidencias van en `docs/evidencias/`. Lista mínima para el informe:

| # | Evidencia | Cómo obtenerla |
|---|---|---|
| 1 | Tests locales en verde | `pytest app/tests -v` |
| 2 | Comparación de tamaño builder vs runtime | `docker images \| grep pf-cloud-api` |
| 3 | Contenedor no root | `docker run --rm pf-cloud-api:1.0.0 id` |
| 4 | `terraform plan` y `apply` | Captura de la terminal |
| 5 | Output de `finops_estimacion` | `terraform output finops_estimacion` |
| 6 | Pods, Service, Ingress y HPA | `kubectl -n pf-app get pods,svc,ingress,hpa` |
| 7 | Respuesta por el Ingress | `curl -i http://pf-cloud.local/healthz` |
| 8 | Workflow de CI en verde | Captura de la pestaña Actions |
| 9 | Hallazgos de SAST | Captura de Security → Code scanning |
| 10 | Reporte de OWASP ZAP | Artifact del job `dast` |
| 11 | Escalado del HPA | `evidencias/hpa-escalado.log` |
| 12 | Dashboard de Grafana con datos | Captura con carga activa |
| 13 | Targets de Prometheus en UP | Captura de Status → Targets |
| 14 | Rolling update sin downtime | `kubectl rollout status` durante `curl` en loop |

---

## Troubleshooting

**El HPA muestra `<unknown>` en TARGETS**
Falta el patch de `--kubelet-insecure-tls` en metrics-server. Ver paso 6.
Verificar con `kubectl top pods -n pf-app`.

**`ImagePullBackOff` en los pods**
La imagen no está en el cluster. Correr
`kind load docker-image pf-cloud-api:1.0.0 --name pf-cloud`.

**El Ingress no responde en `pf-cloud.local`**
Verificar la entrada en `/etc/hosts` y que el cluster se creó con
`scripts/kind-config.yaml` (necesita los `extraPortMappings` de 80 y 443).

**Los pods quedan en `Pending`**
Falta capacidad o se agotó la ResourceQuota. Ver
`kubectl -n pf-app describe resourcequota` y
`kubectl describe pod <nombre>`.

**El chart de Prometheus no termina de instalarse**
Necesita RAM. Subir Docker Desktop a 8 GB, o instalar con
`instalar_monitoreo=false` y desplegar el monitoreo aparte.

**`CrashLoopBackOff` tras activar `readOnlyRootFilesystem`**
La app necesita escribir en `/tmp`. El `emptyDir` montado en `/tmp` del
Deployment lo resuelve; verificar que esté presente.

---

## Autor

Proyecto final — Infraestructura Cloud y Automatización.
Repositorio: `<URL-DEL-REPO>`
