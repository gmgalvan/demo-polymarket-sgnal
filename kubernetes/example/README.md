# Example: vLLM autocomplete en el lane de GPU

Este ejemplo despliega un servidor `vLLM` sobre el lane `gpu` de Karpenter y expone un endpoint compatible con OpenAI en el puerto `8000`.

Lo deje orientado a GPU porque es el camino mas rapido para probar un modelo sobre el cluster actual. La ruta de Inferentia necesita un modelo precompilado, asi que conviene tratarla como un segundo ejemplo despues.

## Que despliega

- Namespace: `ai-example`
- Deployment: `vllm-gpu-autocomplete`
- Service: `vllm-gpu-autocomplete`
- Modelo: `Qwen/Qwen2.5-3B-Instruct`
- Nombre servido por la API: `demo-autocomplete`
- Requests ajustados para que quepa en `g6e.xlarge` con los DaemonSets del nodo

## Apply

Desde el root del repo:

```bash
kubectl apply -k kubernetes/example
```

Si todavia no existe un nodo GPU, Karpenter deberia levantarlo en cuanto vea el pod `Pending`.

Para ver el pod:

```bash
kubectl get pods -n ai-example -w
```

Para ver logs mientras baja el modelo:

```bash
kubectl logs -n ai-example deploy/vllm-gpu-autocomplete -f
```

El primer arranque puede tardar un poco porque el pod descarga los pesos del modelo.

## Flujo validado

Este fue el flujo que ya se probó con exito en el cluster:

```bash
kubectl apply -k kubernetes/example
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
kubectl rollout status deployment/vllm-gpu-autocomplete -n ai-example
kubectl get pods -n ai-example -o wide
```

Cuando el deployment ya este `successfully rolled out`, usa `port-forward` al pod `Running`:

```bash
kubectl port-forward -n ai-example pod/<pod-running> 8000:8000
```

Luego prueba:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @/home/gmgalvan/demo-polymarket-signal/kubernetes/example/request.autocomplete.json
```

## Port-forward

Expone el servicio localmente:

```bash
kubectl port-forward -n ai-example svc/vllm-gpu-autocomplete 8000:8000
```

Deja esa terminal abierta.

## Health check

En otra terminal:

```bash
curl http://127.0.0.1:8000/health
```

Si el modelo ya esta listo, deberias recibir una respuesta sana.

## Probar con curl

Este repo incluye un payload de ejemplo:

- `kubernetes/example/request.autocomplete.json`

Ejecuta:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/example/request.autocomplete.json
```

## Ejemplo inline con tu propio texto

Si quieres mandar tu propio texto directo:

```bash
curl http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "demo-autocomplete",
    "temperature": 0.7,
    "max_tokens": 80,
    "messages": [
      {
        "role": "system",
        "content": "You are DemoAutocomplete. Complete only original text or original lyrics provided by the user. Keep the continuation concise, coherent, and natural. If the user appears to be asking for a continuation of a known song, poem, book passage, or other copyrighted text, do not continue it verbatim. Instead, offer a brief summary or write a fresh original continuation with different wording."
      },
      {
        "role": "user",
        "content": "Completa este texto original manteniendo un tono pop suave: Cuando la ciudad se apaga y las luces del puente se encienden, yo..."
      }
    ]
  }'
```

## Como cambiar el prompt

- Reemplaza el contenido del `user` con tu propio texto o tus propios versos.
- Deja `model` como `demo-autocomplete`.
- Ajusta `temperature` si quieres mas o menos creatividad.
- Sube `max_tokens` si quieres una continuacion mas larga.

## Nota importante sobre letras de canciones

Este ejemplo esta preparado para autocompletar texto original que tu le pases.

No esta configurado para continuar de forma literal letras de canciones conocidas ni otro texto protegido. Si pegas lineas de una cancion conocida, el comportamiento seguro es rechazar la continuacion literal y ofrecer un resumen o una continuacion nueva y original.

## Troubleshooting

### El pod se queda `Pending`

Eso puede ser normal al inicio. El deployment pide:

- `workload=gpu`
- `nvidia.com/gpu: 1`

Si no existe un nodo GPU libre, Karpenter primero crea un `NodeClaim` y luego el nodo EC2. Observa:

```bash
kubectl get nodeclaims -w
kubectl get pods -n ai-example -w
```

### `kubectl logs` no muestra nada y dice `ContainerCreating`

Eso significa que el contenedor todavia no arranca. Primero esta:

- descargando la imagen
- desempaquetando capas
- arrancando `vLLM`

En ese momento es mejor revisar eventos:

```bash
kubectl describe pod -n ai-example <pod>
kubectl get events -n ai-example --sort-by=.metadata.creationTimestamp | tail -n 30
```

### `port-forward` al servicio falla con `connection refused`

Eso puede pasar si hiciste `kubectl apply` y el rollout todavia no termina. Primero confirma:

```bash
kubectl rollout status deployment/vllm-gpu-autocomplete -n ai-example
kubectl get pods -n ai-example -o wide
```

Cuando ya haya un pod `Running`, usa `port-forward` al pod, no al servicio:

```bash
kubectl port-forward -n ai-example pod/<pod-running> 8000:8000
```

### Fallo por `no space left on device`

Ese problema ya fue corregido en la infraestructura aumentando el disco raíz de los nodos Karpenter GPU. Si vuelves a ver algo como:

- `ErrImagePull`
- `no space left on device`
- `The node was low on resource: ephemeral-storage`

entonces:

1. reaplica Terraform del stack EKS
2. elimina el example
3. borra los `NodeClaim` GPU viejos
4. vuelve a aplicar el example

Comandos:

```bash
cd infrastructure/lv-2-core-compute/eks
terraform apply -var='enable_karpenter_resources=true' -var='enable_karpenter_nodepools=true'

kubectl delete -k /home/gmgalvan/demo-polymarket-signal/kubernetes/example --ignore-not-found
kubectl get nodeclaims
kubectl delete nodeclaim <gpu-nodeclaim-viejo>

cd /home/gmgalvan/demo-polymarket-signal
kubectl apply -k kubernetes/example
```

## Limpiar

```bash
kubectl delete -k kubernetes/example
```

Si quieres acelerar el apagado del costo GPU, puedes borrar tambien los `NodeClaim` GPU manualmente en vez de esperar la consolidacion de Karpenter:

```bash
kubectl get nodeclaims
kubectl delete nodeclaim <gpu-nodeclaim>
```
