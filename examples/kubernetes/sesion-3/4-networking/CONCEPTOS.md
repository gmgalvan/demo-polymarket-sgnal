# Guía para explicar networking de Kubernetes

Esta guía acompaña al laboratorio de `4-networking`. Resume los fundamentos que
conviene explicar en la sesión y separa los temas avanzados de GenAI que pueden
dejarse como referencia.

## La idea principal

Kubernetes necesita resolver tres problemas distintos:

1. Dar conectividad e IP a cada Pod.
2. Dar una identidad estable a una aplicación cuyos Pods pueden cambiar.
3. Permitir que otros componentes encuentren esa identidad por nombre.

En el clúster de esta demostración, esos trabajos se reparten así:

```text
Amazon VPC CNI -> conecta los Pods y les asigna IP
Service        -> proporciona una IP virtual estable
EndpointSlice  -> registra las IP actuales de los Pods preparados
CoreDNS        -> convierte nombres de Services en direcciones
Ingress        -> declara reglas HTTP de entrada desde fuera del clúster
Controller     -> implementa realmente las reglas del Ingress
```

Frase de apertura sugerida:

> En Kubernetes los Pods son reemplazables, por lo que su dirección IP también
> puede cambiar. La red permite comunicación directa entre Pods, mientras que
> Services y DNS proporcionan la identidad estable que usan las aplicaciones.

## Qué sucede cuando nace un Pod

Una explicación simplificada y suficientemente precisa es:

1. El scheduler asigna el Pod a un worker node.
2. El kubelet de ese nodo solicita al runtime crear el sandbox del Pod.
3. El kubelet invoca el plugin CNI para configurar su red.
4. El IPAM del Amazon VPC CNI reserva una dirección de una subnet de la VPC.
5. El CNI configura la interfaz y las rutas necesarias.
6. Kubernetes publica esa dirección como `status.podIP`.

En EKS, `aws-node` es un DaemonSet porque cada worker necesita un agente local
del VPC CNI.

No es necesario explicar en detalle interfaces ENI, tablas de rutas o reglas de
kernel durante la primera demo. Basta con mostrar:

```bash
kubectl get daemonset aws-node --namespace kube-system
kubectl get pods --namespace sesion-3 --output wide
```

## Las tres direcciones que no se deben confundir

| Dirección | Ejemplo | Función | ¿Puede cambiar? |
|---|---|---|---|
| Pod IP | `10.40.4.101` | Identifica una instancia concreta | Sí, al reemplazar el Pod |
| Service ClusterIP | `172.20.50.10` | Destino virtual estable dentro del clúster | No, mientras exista el Service |
| Ingress/LB address | DNS de un ALB | Entrada HTTP desde otra red | La administra el controller/cloud |

Mensaje sugerido:

> Pod IP responde a “¿dónde está esta réplica ahora?”. Service responde a “¿cómo
> encuentro siempre esta aplicación?”.

## Comunicación Pod-to-Pod

El modelo de Kubernetes establece que cada Pod tiene una IP propia y que, salvo
que una política lo restrinja, los Pods pueden comunicarse directamente aunque
estén en nodos distintos.

Los contenedores dentro de un mismo Pod comparten el namespace de red:

- Comparten la IP del Pod.
- Pueden comunicarse entre sí mediante `localhost`.
- No pueden escuchar simultáneamente en el mismo puerto.

En la demo, `network-client` llama directamente la IP de `model-api`. Esto
demuestra la conectividad del CNI, pero no representa la forma recomendada de
configurar una aplicación porque esa IP desaparecerá al reemplazar el Pod.

## Service y EndpointSlice

Un Service selecciona Pods mediante labels:

```yaml
selector:
  app: model-api
```

Los Pods seleccionados tienen la misma label:

```yaml
labels:
  app: model-api
```

Kubernetes crea y actualiza EndpointSlices con las direcciones de los Pods que
están preparados. El Service mantiene su identidad aunque esos endpoints
cambien.

Flujo que debes narrar:

```text
Petición a model-api:80
        -> Service model-api
        -> EndpointSlice
        -> uno de los Pods Ready
```

La readiness probe es importante: un backend que todavía no está preparado no
debe recibir tráfico del Service. En un servidor GenAI real, el endpoint de
salud debería indicar que el modelo terminó de cargar y que la inferencia está
operativa.

### Tipos de Service

| Tipo | Uso típico |
|---|---|
| `ClusterIP` | Comunicación interna entre componentes; es el default |
| `NodePort` | Expone un puerto en cada nodo; útil en pruebas puntuales |
| `LoadBalancer` | Solicita un balanceador del proveedor de nube |
| `ExternalName` | Devuelve un alias DNS hacia un servicio externo |

Para el laboratorio usamos `ClusterIP` porque primero queremos entender la red
interna sin crear infraestructura de AWS ni generar costos adicionales.

## CoreDNS y descubrimiento de servicios

CoreDNS permite que una aplicación use nombres en lugar de direcciones IP.

Dentro del mismo namespace basta con:

```text
model-api
```

Desde cualquier namespace puede utilizarse el nombre completo:

```text
model-api.sesion-3.svc.cluster.local
```

CoreDNS resuelve normalmente ese nombre a la ClusterIP del Service. Después, el
data plane del Service dirige la conexión hacia uno de los endpoints preparados.

Mensaje sugerido:

> DNS encuentra el Service; el Service encuentra un Pod preparado. CoreDNS no
> balancea las peticiones y el CNI no resuelve nombres.

## Ingress y su controller

Un Ingress es un objeto declarativo con reglas HTTP/S. Puede decidir el backend
por hostname o path:

```text
/model/*  -> model-api
/signal/* -> signal-api
```

Pero el manifiesto por sí solo no mueve tráfico. Hace falta un Ingress
Controller que observe el objeto y configure la infraestructura real.

En AWS, el flujo planeado sería:

```text
Cliente solicita http://k8s.demo.gmgalvan.com/model/
  -> Route 53
  -> Application Load Balancer
  -> regla /model o /signal
  -> Service ClusterIP
  -> EndpointSlice
  -> Pod
```

La demo utiliza una clase `alb` y `target-type: ip`. Este target type permite
que el ALB registre direcciones de Pods en vez de depender de un salto NodePort.
Se eligió explícitamente un ALB `internet-facing` para poder asociar el nombre
público `k8s.demo.gmgalvan.com`. Esto genera costo y exposición pública; debe
eliminarse al terminar la demostración.

Route 53 solamente resuelve el nombre hacia el ALB. No reemplaza al Ingress,
Service, EndpointSlice ni CoreDNS. Route 53 atiende el nombre público; CoreDNS
atiende nombres internos como `model-api.sesion-3.svc.cluster.local`.

La primera versión puede demostrarse mediante HTTP. Para HTTPS se requiere un
certificado ACM validado y configurar el listener TLS del ALB.

El clúster actual no tiene una `IngressClass`, por lo que el ejemplo debe
explicarse sin aplicarlo hasta instalar intencionalmente AWS Load Balancer
Controller.

Mensaje sugerido:

> Ingress expresa la intención de routing. El controller convierte esa
> intención en un balanceador y reglas reales. Sin controller, el Ingress es
> solamente configuración almacenada en la API.

## Por qué esto importa para GenAI

- Un Pod de inferencia puede tardar minutos en descargar y cargar un modelo.
  Readiness evita enviarle peticiones antes de tiempo.
- Los Pods GPU también son reemplazables; los consumidores deben usar un
  Service y no guardar sus IPs.
- Una plataforma puede exponer varios modelos bajo un dominio y enrutar por
  path o hostname mediante Ingress o Gateway API.
- La inferencia sensible a latencia se beneficia de evitar saltos innecesarios
  y de usar networking nativo como Amazon VPC CNI.
- En clusters grandes hay que vigilar capacidad de IPs, latencia DNS, throughput
  y health checks, pero no son necesarios para entender esta primera demo.

## Temas avanzados del capítulo que quedan fuera del laboratorio

Puedes mencionarlos al final sin demostrarlos:

- `NetworkPolicy`: aislamiento L3/L4 por labels, namespaces, puertos e IPs.
- Service mesh: observabilidad, mTLS, reintentos y routing L7 entre servicios.
- Gateway API: evolución más extensible para routing que también requiere un
  controller.
- NodeLocal DNSCache y autoscaling de CoreDNS: optimizaciones para clusters con
  muchas consultas DNS.
- eBPF, SR-IOV, placement groups y EFA: optimizaciones avanzadas para baja
  latencia, alto throughput o entrenamiento distribuido multi-node.

No conviene incluirlos en la explicación principal porque desvían la atención
del flujo fundamental:

```text
Pod -> DNS -> Service -> EndpointSlice -> Pod
```

## Matices técnicos del material de referencia

El archivo adjunto es un resumen parafraseado del capítulo, no el PDF original.
Resulta útil para estructurar la lección, pero algunas frases necesitan estos
matices antes de presentarlas como reglas generales:

- El runtime crea normalmente el sandbox y el network namespace del Pod; el CNI
  configura la interfaz, dirección y conectividad de ese namespace. Decir
  simplemente que “el CNI crea todo el namespace” mezcla responsabilidades.
- La API estándar de Ingress define coincidencias por host y path. Routing por
  headers, pesos o canary depende de extensiones del controller o de APIs como
  Gateway API; no es una capacidad portable del Ingress básico.
- Una readiness probe decide si el Pod entra en los endpoints preparados del
  Service. Una liveness probe puede provocar el reinicio del contenedor. Un
  health check del ALB/NLB retira temporalmente un target, pero por sí solo no
  reemplaza el Pod. Son tres mecanismos relacionados, no equivalentes.
- Cilium puede operar con distintos modos de datapath. No debe clasificarse
  siempre como networking nativo sin revisar su configuración concreta.
- La recomendación histórica de cambiar kube-proxy de `iptables` a `ipvs` está
  desactualizada para Kubernetes moderno. Kubernetes 1.35 depreca IPVS y
  recomienda evaluar `nftables` en Linux. En EKS administrado no se debe cambiar
  el modo durante esta clase ni sin validar soporte y compatibilidad.
- Instalar el add-on administrado de CoreDNS no significa que su autoscaling
  esté habilitado automáticamente. En EKS es una opción que debe configurarse y
  verificarse.
- Crear un objeto `NetworkPolicy` no garantiza que se aplique: el plugin de red
  y su configuración deben soportar enforcement. Antes de una demo se debe
  comprobar la configuración efectiva del VPC CNI.
- Custom networking de VPC CNI permite usar subnets alternativas, normalmente
  creadas desde un CIDR secundario de la VPC. El uso de espacio compartido como
  `100.64.0.0/10`, sus rutas y su conectividad requieren diseño explícito; no
  basta con describir cualquier CIDR secundario como simplemente “no enrutable”.

Estos matices no cambian el laboratorio básico, pero evitan presentar una
optimización avanzada como una propiedad universal de Kubernetes.

## Errores comunes que debes evitar al explicar

- “El Service es otro Pod”: no; es una abstracción y una dirección virtual.
- “CoreDNS devuelve siempre la IP del backend”: para un Service ClusterIP
  normal devuelve la ClusterIP.
- “El CNI hace balanceo”: el CNI configura conectividad; no sustituye al
  Service.
- “Ingress funciona apenas aplico el YAML”: necesita un controller.
- “Running significa listo”: un Pod puede estar ejecutándose mientras el
  modelo todavía carga; para tráfico importa `Ready`.
- “Una Pod IP es permanente”: se puede reemplazar junto con el Pod.

## Guion breve de cinco minutos

1. Mostrar `aws-node` y decir que el CNI conecta los Pods y asigna sus IPs.
2. Mostrar `kubectl get pods -o wide` y llamar directamente una Pod IP.
3. Explicar por qué esa IP es efímera y crear el Service.
4. Mostrar EndpointSlice, resolver `model-api` y llamar al Service por DNS.
5. Reemplazar un Pod, observar la nueva IP y usar el mismo nombre de Service.
6. Cerrar con el diagrama de Ingress y aclarar que requiere un controller.
