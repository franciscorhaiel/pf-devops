# Guia para armar el informe PF+APELLIDO.pdf

El informe es un entregable **distinto** del repositorio. El repo tiene el
codigo; el informe explica el proceso y muestra las evidencias.

## Estructura recomendada (12 a 18 paginas)

### 1. Portada
Nombre, apellido, comision, fecha, URL del repositorio.

### 2. Resumen ejecutivo (media pagina)
Que se construyo, con que stack, y el resultado. Que alguien lo lea y entienda
el alcance sin leer el resto.

### 3. Arquitectura (1 a 2 paginas)
El diagrama del README. Explicar el recorrido de una request: Ingress → Service
→ Pod, y como el HPA observa metricas via metrics-server.

### 4. Docker y multi-stage (2 paginas)
- Las tres etapas y que hace cada una
- **Evidencia clave:** tabla comparativa de tamano builder vs runtime
- Por que la etapa `tester` corre dentro del build
- Evidencia de que el contenedor no corre como root

### 5. Terraform (2 paginas)
- Los dos modulos y por que estan separados
- Las variables con validaciones
- **Evidencia:** captura de `terraform plan` y de `terraform output finops_estimacion`
- Mencionar que reemplazar `kind_cluster` por EKS/GKE no requiere tocar `k8s_app`

### 6. Pipeline CI/CD (3 paginas)
- Tabla de los 4 jobs de CI y los 2 de CD
- Las herramientas de SAST (Bandit, Semgrep, Gitleaks, Checkov) y DAST (ZAP)
- **Evidencias:** captura del workflow en verde, de Security → Code scanning,
  y del reporte de ZAP
- Como se manejan los secretos

### 7. Kubernetes (2 paginas)
- Los 7 manifiestos y su rol
- Probes: liveness, readiness, startup, y para que sirve cada una
- **Evidencia:** `kubectl -n pf-app get pods,svc,ingress,hpa`

### 8. Auto-escalado (1 a 2 paginas)
- Configuracion del HPA y por que el `behavior` es asimetrico
- **Evidencia estrella:** el log de `hpa-escalado.log` mostrando la progresion
  de 2 a 6 replicas y la vuelta a 2

### 9. Monitoreo (2 paginas)
- Los 6 paneles del dashboard
- Las alertas configuradas
- **Evidencias:** captura de Grafana con datos, y de Prometheus → Targets en UP

### 10. FinOps (2 paginas)
- La tabla de las 7 medidas
- El calculo: USD 5.12 piso vs USD 25.60 techo, 69% de ahorro
- Explicar por que requests y limits son la base de todo calculo de costo

### 11. Seguridad (1 pagina)
La tabla de controles del README.

### 12. Problemas encontrados y como se resolvieron (1 pagina)
**Esta seccion suele diferenciar un informe bueno de uno excelente.** Ejemplos
reales de este proyecto:
- El HPA mostraba `<unknown>`: faltaba `--kubelet-insecure-tls` en metrics-server
- `CrashLoopBackOff` al activar `readOnlyRootFilesystem`: hubo que montar un
  emptyDir en /tmp
- El Ingress no respondia: faltaban los `extraPortMappings` en la config de kind

### 13. Conclusiones y proximos pasos
Que se aprendio y que faltaria para produccion (backend remoto de Terraform con
state lock, cert-manager para TLS, ArgoCD para GitOps, Karpenter o spot
instances para FinOps real).

### 14. Anexos
Links al repositorio, a los workflows ejecutados y a los archivos clave.

## Consejos de presentacion

- Toda captura debe tener epigrafe: "Figura 4: escalado del HPA de 2 a 6
  replicas bajo carga de 30 clientes concurrentes"
- Los bloques de codigo largos van en anexo o se referencian por link al repo,
  no pegados en el cuerpo
- Cada afirmacion tecnica que puedas respaldar con una captura, respaldala

## Commits

El enunciado pide commits claros. Sugerencia de secuencia:

```
feat: app FastAPI con health checks y metricas Prometheus
feat: Dockerfile multi-stage de 3 etapas con usuario no root
feat: modulos Terraform para cluster kind y aplicacion
feat: manifiestos Kubernetes con HPA, PDB y NetworkPolicy
ci: workflow de build, test, SAST y DAST
ci: workflow de deploy con Terraform y validacion end-to-end
feat: monitoreo con Prometheus, Grafana y alertas
feat: medidas FinOps y apagado fuera de horario
docs: README con instrucciones de reproduccion y evidencias
```
