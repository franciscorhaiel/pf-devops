# FinOps: optimizacion de costos

Las siete medidas aplicadas en este proyecto, con el mecanismo concreto
que las implementa y el ahorro que persiguen.

| # | Medida | Donde esta implementada | Ahorro que persigue |
|---|--------|-------------------------|---------------------|
| 1 | Imagen minima con multi-stage | `Dockerfile` (3 etapas) | Menos almacenamiento en registry, pull mas rapido, menos superficie de ataque |
| 2 | Requests y limits ajustados | `k8s/10-deployment.yaml`, `terraform/variables.tf` | Evita reservar CPU/RAM que no se usa (el costo se cobra por request, no por uso) |
| 3 | Auto-escalado horizontal | `k8s/40-hpa.yaml` | Solo se paga por replicas cuando hay demanda real |
| 4 | Scale-down conservador | `behavior.scaleDown` del HPA | Evita el flapping, que genera churn de pods y costo de arranque |
| 5 | ResourceQuota y LimitRange | `terraform/modules/k8s_app/main.tf` | Techo duro: ningun deploy mal configurado consume el cluster |
| 6 | Apagado fuera de horario | `finops/kube-downscaler.yaml` | ~70% de ahorro en entornos no productivos (16h/dia + fines de semana apagado) |
| 7 | Alertas de sobreaprovisionamiento | `monitoring/alertas.yaml` | Detecta recursos pagados y no usados antes de que se vuelvan cronicos |

## Calculo de costo

El output `finops_estimacion` de Terraform calcula:

```
costo_minimo = memoria_request_MB x min_replicas x costo_por_MB
costo_maximo = memoria_request_MB x max_replicas x costo_por_MB
```

Con los valores por defecto (128Mi, 2-10 replicas, USD 0.02/MB/mes):

- Piso: 128 x 2 x 0.02 = **USD 5.12/mes**
- Techo: 128 x 10 x 0.02 = **USD 25.60/mes**

Sin HPA habria que aprovisionar para el pico permanente: USD 25.60/mes fijos.
Con HPA y una carga que solo pica 4 horas al dia, el costo real ronda los
USD 8/mes. **Ahorro estimado: 69%.**

## Apagado fuera de horario

`kube-downscaler` apaga los deployments del namespace fuera de la ventana
laboral. Aplicado solo a entornos de prueba, nunca a produccion.

```bash
kubectl apply -f finops/kube-downscaler.yaml
```
