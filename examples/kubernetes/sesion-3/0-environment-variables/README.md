# Variables de entorno en Kubernetes

Este laboratorio introduce las variables de entorno antes de agregar
ConfigMaps y Secrets.

La progresión conceptual es:

```text
Valor directo             ConfigMap                  Secret
env.value                 configMapKeyRef/envFrom    secretKeyRef
     |                           |                       |
     +---------------------------+-----------------------+
                                 |
                                Pod
```

En este primer ejercicio solo usamos `env.value`. Los otros dos mecanismos se
presentan después para mostrar cómo separar la configuración de la definición
del workload.

## Idea para explicarlo

Docker permite inyectar una variable al iniciar un contenedor:

```bash
docker run --env APP_COLOR=lightpink busybox
```

Kubernetes expresa la misma intención de manera declarativa dentro del Pod:

```yaml
env:
  - name: APP_COLOR
    value: "lightpink"
```

La imagen no cambia. Solamente cambia la configuración entregada cuando
Kubernetes crea el contenedor.

## Qué despliega el ejemplo

`01-plain-env.yaml` contiene:

- Un Deployment con una réplica.
- Dos variables directas: `APP_COLOR` y `APP_MODE`.
- Un servidor HTTP pequeño basado en BusyBox.
- Un Service de tipo `ClusterIP`.

Al arrancar, el contenedor genera una página HTML usando los valores de las
variables de entorno.

## Ejecutar

Desde la raíz del repositorio:

```bash
kubectl apply --filename examples/kubernetes/sesion-3/00-namespace.yaml
kubectl apply --filename examples/kubernetes/sesion-3/0-environment-variables/01-plain-env.yaml

kubectl rollout status deployment/env-color-demo \
  --namespace sesion-3
```

## Inspeccionar la definición

```bash
kubectl get deployment env-color-demo \
  --namespace sesion-3 \
  --output yaml
```

Mostrar únicamente la sección relevante:

```bash
kubectl get deployment env-color-demo \
  --namespace sesion-3 \
  --output jsonpath='{.spec.template.spec.containers[0].env}'
```

## Ver las variables dentro del contenedor

```bash
kubectl exec \
  --namespace sesion-3 \
  deployment/env-color-demo -- \
  printenv APP_COLOR APP_MODE
```

Salida esperada:

```text
lightpink
demo
```

También se puede inspeccionar el ambiente completo:

```bash
kubectl exec \
  --namespace sesion-3 \
  deployment/env-color-demo -- \
  env
```

## Ver el resultado HTTP

En una terminal:

```bash
kubectl port-forward \
  --namespace sesion-3 \
  service/env-color-demo \
  8080:8080
```

En otra terminal:

```bash
curl http://127.0.0.1:8080
```

También se puede abrir `http://127.0.0.1:8080` en el navegador. La página debe
tener fondo rosa. El valor de `APP_COLOR` no se imprime en el HTML: su efecto
se demuestra visualmente mediante el color de fondo.

## Cambiar una variable

Este comando modifica la plantilla del Deployment. Kubernetes crea un nuevo
Pod porque las variables de entorno se establecen al iniciar el contenedor:

```bash
kubectl set env deployment/env-color-demo \
  --namespace sesion-3 \
  APP_COLOR=lightgreen \
  APP_MODE=updated

kubectl rollout status deployment/env-color-demo \
  --namespace sesion-3
```

Comprobar el nuevo valor:

```bash
kubectl exec \
  --namespace sesion-3 \
  deployment/env-color-demo -- \
  printenv APP_COLOR APP_MODE
```

Recargar la página. Ahora el fondo debe cambiar de rosa a verde sin mostrar el
nombre del color en el texto de la página.

## Mensajes clave

- La imagen del contenedor permanece igual.
- `env.value` es apropiado para valores pequeños y específicos del workload.
- Cambiar una variable de la plantilla provoca un rollout del Deployment.
- Repetir muchos valores directamente en varios workloads genera duplicación.
- ConfigMap resuelve esa duplicación al convertir la configuración en un
  recurso independiente.
- No se deben colocar contraseñas o tokens en `env.value`.

## Transición hacia ConfigMaps

Pregunta sugerida para la audiencia:

> ¿Qué sucede si diez Deployments necesitan `MODEL_PROVIDER`, `MODEL_NAME` y
> `LOG_LEVEL`, y debemos modificarlos juntos?

La respuesta conduce al siguiente laboratorio:

```text
../configmaps/
```

## Limpieza

```bash
kubectl delete --filename examples/kubernetes/sesion-3/0-environment-variables/01-plain-env.yaml
```
