# Demo Runbook: Inferentia + vLLM + Observability

Este runbook es una guía corta para una demo en vivo del stack:

- modelo TinyLlama corriendo en AWS Inferentia
- métricas de vLLM en Grafana
- métricas de Neuron runtime en Grafana

La idea es mostrar:

1. que el modelo responde
2. que observabilidad está activa
3. cómo cambian latencia, throughput y uso del acelerador bajo concurrencia
4. un tradeoff simple de optimización en vivo

---

## 0) Pre-check rápido

Verifica que el port-forward del servicio siga activo:

```bash
curl http://127.0.0.1:8000/health
```

Si responde, el endpoint está listo.

Si no responde, vuelve a abrir el port-forward:

```bash
kubectl port-forward -n ai-example svc/vllm-neuron-tinyllama-1b 8000:8000
```

En otra terminal, deja abierto Grafana en:

- `vLLM Model Serving`
- `AWS Neuron — Inferentia/Trainium Metrics`

Recomendación:
- time range: `Last 5 minutes`
- refrescar manualmente después de cada paso

---

## 1) Mostrar que el modelo responde

Comando:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2/request.chat-test.json
```

Qué panel mirar:

- `vLLM Model Serving`
  - `Time to First Token (TTFT)`
  - `End-to-End Request Latency`

Qué decir:

- “Aquí estoy haciendo una inferencia real contra TinyLlama sobre Inferentia.”
- “TTFT me dice qué tan rápido empieza a responder.”
- “End-to-end me dice cuánto tarda toda la respuesta.”

---

## 2) Mostrar que Neuron sí está siendo usado

Qué panel mirar:

- `AWS Neuron — Inferentia/Trainium Metrics`
  - `NeuronCore Utilization (%)`
  - `Device Memory Used (GiB)`
  - `Neuron Monitor Scrape Up`

Qué decir:

- “Aquí vemos uso real del acelerador, no solo una app devolviendo texto.”
- “Los picos en NeuronCore Utilization significan trabajo real de inferencia.”
- “La memoria del device muestra cuánto del acelerador está ocupado por el modelo/runtime.”
- “Scrape Up = 1 confirma que Prometheus está recolectando estas métricas.”

Cómo leerlo:

- `NeuronCore Utilization (%)`
  - muestra cuánto trabaja cada core
  - picos altos significan inferencia activa
- `Device Memory Used (GiB)`
  - memoria usada dentro del acelerador
  - estable significa que el modelo ya está cargado
- `Neuron Monitor Scrape Up`
  - `1` = el monitoreo está sano

---

## 3) Generar carga concurrente

Usa el script async:

```bash
cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
python3 load_test_async.py --requests 10 --concurrency 5 --print-samples 2
```

Qué panel mirar:

- `vLLM Model Serving`
  - `Request Throughput (QPS)`
  - `Token Throughput (tokens/sec)`
  - `Requests Waiting / Running`
  - `End-to-End Request Latency`
  - `Approx Time per Output Token (TPOT / ITL avg)`
- `AWS Neuron — Inferentia/Trainium Metrics`
  - `NeuronCore Utilization (%)`

Qué decir:

- “Ahora mando varias requests concurrentes para generar presión.”
- “Aquí debería subir el throughput de requests y de tokens.”
- “Si aparece cola en Waiting, significa que el servicio ya está empezando a saturarse.”
- “Si sube E2E latency bajo concurrencia, ya vemos el tradeoff entre throughput y latencia.”

Cómo interpretar lo que ves:

- `Request Throughput (QPS)`
  - cuántas requests por segundo atiende el servicio
- `Token Throughput (tokens/sec)`
  - cuántos tokens procesa por segundo
  - suele ser más útil que QPS para LLMs
- `Requests Waiting / Running`
  - `Waiting` = requests en cola
  - `Running` = requests activas
- `Approx TPOT`
  - aproximación del tiempo promedio por token de salida
  - si sube, la generación se siente menos fluida

---

## 4) Cómo decir si hubo saturación o no

Si ves algo como:

- `Waiting > 0`
- `E2E latency` sube notablemente
- `NeuronCore Utilization` se acerca a picos altos

Puedes decir:

- “Aquí no colapsó el servicio, pero sí mostró presión.”
- “Ya aparece cola y la latencia total sube, así que vemos saturación parcial.”

Si no aparece cola y todo sigue bajo:

- “Todavía hay margen; el servicio absorbió esta carga sin saturarse.”

---

## 5) Optimización en vivo recomendada

La optimización más fácil de explicar en demo no es cambiar infraestructura, sino cambiar concurrencia.

### Opción A: mostrar presión

```bash
python3 load_test_async.py --requests 10 --concurrency 5
```

### Opción B: mostrar mejora bajando concurrencia

```bash
python3 load_test_async.py --requests 10 --concurrency 2
```

Qué decir:

- “Sin tocar infraestructura, puedo cambiar el nivel de concurrencia.”
- “Con menos concurrencia, baja la cola y mejora la latencia.”
- “El tradeoff es que también baja el throughput agregado.”

Qué deberías ver:

- menor `Requests Waiting`
- menor `End-to-End Request Latency`
- `Token Throughput` más estable
- menor presión visible en `NeuronCore Utilization`

Esta es la optimización más segura para demo porque:

- no depende de reprovisionar nodos
- no cambia el modelo
- no depende de rebuilds
- el efecto es fácil de explicar

---

## 6) Cómo explicar el dashboard de vLLM

`TTFT`
- qué tan rápido empieza a responder

`Approx TPOT`
- qué tan fluida es la salida token por token

`End-to-End Latency`
- cuánto tarda toda la respuesta

`QPS`
- cuántas solicitudes por segundo procesa

`Token Throughput`
- capacidad real del modelo en tokens por segundo

`Requests Waiting / Running`
- si hay cola y si el sistema se está saturando

`Tokens Processed in Selected Range`
- cuántos tokens de entrada y salida se procesaron en la ventana visible del dashboard

---

## 7) Guion corto hablado

Versión rápida de 30-45 segundos:

- “Aquí tengo TinyLlama corriendo sobre AWS Inferentia y respondiendo por una API compatible con OpenAI.”
- “En Grafana veo dos capas: vLLM, que me da latencia, throughput y cola; y Neuron, que me muestra uso real del acelerador.”
- “Cuando mando carga concurrente, suben throughput y utilización, pero también puede subir la latencia o aparecer cola.”
- “Eso me deja mostrar el tradeoff clásico: más capacidad aprovechada contra peor experiencia si empujo demasiado la concurrencia.”

---

## 8) Comandos listos

Request simple:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d @kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2/request.chat-test.json
```

Carga moderada:

```bash
cd kubernetes/examples/manual-model-deployment/04-vllm-neuron-tinyllama-1b-inf2
python3 load_test_async.py --requests 10 --concurrency 5 --print-samples 2
```

Carga más suave:

```bash
python3 load_test_async.py --requests 10 --concurrency 2
```

---

## 9) Qué no cambiar en vivo

Evita durante la demo:

- rebuild del contenedor Neuron
- cambio de modelo
- escalar a otra réplica si depende de aprovisionar otro `inf2`
- tocar Terraform

Para demo, lo más estable es:

- mismo modelo
- mismo endpoint
- cambiar solo la carga
- leer el efecto en Grafana

---

## 10) Nota para GPU L40S

En esta demo con `Qwen 2.5 3B` sobre `NVIDIA L40S`, puede pasar que:

- `DCGM_FI_DEV_GPU_UTIL` permanezca en `0`
- aunque el modelo sí esté funcionando y respondiendo

Eso no significa que la GPU esté inactiva.

En ese caso, usa estos paneles como señal principal de actividad real:

- `GPU Memory Used (GiB)`
- `GPU Power Draw (W)`
- `SM Clock (MHz)`
- `Xid Errors`

Cómo explicarlo:

- “La mejor evidencia aquí no es solo GPU utilization.”
- “La memoria alta confirma que el modelo está cargado.”
- “El power draw y el SM clock muestran que la GPU sí está trabajando.”
- “Xid en cero confirma que no estamos viendo errores del driver.”

Si además el dashboard de `vLLM Model Serving` muestra:

- `QPS`
- `Token Throughput`
- `End-to-End Latency`

entonces ya tienes evidencia suficiente de serving + uso real del acelerador, aunque `GPU Utilization (%)` no sea el mejor indicador visual en esta L40S.
