# Guión — Bug 3: la base de datos

Guión hablado para las slides **16 (Break 3)** y **17 (Investigate 3)**.
Escrito para decirse, no para leerse: frases cortas, en voz alta.

`[ACCIÓN]` = qué hacer con el mouse. `[PAUSA]` = callarse y dejar que caiga.

Duración estimada: **6–8 minutos**.

**Antes de empezar:** Mongo tiene que estar arriba.
`kubectl -n session-5 get pods` debe mostrar 5 Pods Running.

---

## Slide 16 — Take the database away

### Entrada (~30s)

> Vamos con el último. Y este es distinto a los dos anteriores.
>
> En el primero rompimos un tag de imagen. En el segundo, un selector.
> En los dos había un error: algo mal escrito, algo que un code review
> hubiera atajado.
>
> Acá no voy a escribir nada mal. No voy a romper ningún objeto.
> Voy a hacer una operación **perfectamente legítima**, de esas que hacés
> un martes a la tarde sin pensarlo.

### El break (~45s)

> Voy a bajar la base de datos a cero réplicas.

`[ACCIÓN] Click en el paso 01 → Enter`

> Listo. Mongo ya no existe.
>
> Fíjense que el volumen sigue ahí — el EBS no se borra, esto no es
> destructivo. Simplemente no hay ningún Pod corriendo Mongo.

`[PAUSA]`

> Ahora la pregunta obvia: ¿qué le pasó a la aplicación?

### La pregunta (~1 min)

> No voy a mirar Kubernetes todavía. Voy a hacer lo que haría un usuario:
> entrar y preguntar algo.

`[ACCIÓN] Click en el paso 02 → Enter`

> Y me contesta.
>
> Me contesta bien. "Inflation is the widespread and sustained rise in
> the prices of goods and services." Es la respuesta correcta.
> HTTP 200.

`[PAUSA — dejar 3 segundos]`

> Le saqué la base de datos hace veinte segundos.

`[ACCIÓN] Si hay tiempo: abrir finance.gmgalvan.com y preguntar 2–3 veces en la UI]`

> Y no es que tuvo suerte. Pregunten lo que quieran, contesta siempre.
>
> Así que... ¿está todo bien? ¿Bajamos la base y no pasó nada?

---

## Slide 17 — Kubernetes says everything is fine

### Arranque (~20s)

> Vamos a investigarlo como investigamos los otros dos.
> Mismo método, de abajo hacia arriba.

### Paso 01 — los Pods (~40s)

`[ACCIÓN] Click paso 01 → Enter`

> Todos los Pods: uno de uno, Running, cero restarts.
>
> Mongo no aparece — obvio, lo bajamos nosotros. Pero miren el backend:
> impecable. Ningún restart, ningún CrashLoop, ningún warning.
>
> En el bug 1, acá había un Pod rojo. Acá no hay nada rojo.

### Paso 02 — los Endpoints (~40s)

`[ACCIÓN] Click paso 02 → Enter`

> Los dos backends siguen registrados en el Service.
>
> En el bug 2, este comando era la respuesta: Endpoints vacío.
> Acá está lleno. El tráfico llega perfecto.
>
> O sea: las dos herramientas que nos salvaron en los bugs anteriores
> acá no dicen absolutamente nada.

`[PAUSA]`

### Paso 03 — el probe que miente (~1.5 min) ← **el núcleo**

> Bueno, pero nosotros tenemos un health check. Vamos a preguntarle.

`[ACCIÓN] Click paso 03 → Enter`

> Miren bien esto.
>
> `"status": "ok"`. Y dos campos más allá: `"database": "unreachable"`.
>
> El endpoint **sabe** que la base no está. Lo dice. Lo tiene escrito ahí.

`[PAUSA — 3 segundos]`

> Y devuelve **200**.
>
> Y el readiness probe le pega a este endpoint. Kubelet hace la request,
> ve un 200, y dice "listo, este Pod está sano, mandale tráfico".
>
> Kubelet **nunca lee el body**. Le importa el código de estado y nada más.
>
> Entonces el probe está funcionando perfecto. Está haciendo exactamente
> lo que le pedimos. El problema es que le pedimos mal.
>
> Un probe verifica lo que vos le dijiste que verifique — no lo que
> vos querías decir.

### Paso 04 — el cero silencioso (~1 min)

> Bueno, ¿y los datos? Acabo de hacer tres preguntas. Vamos a verlas.

`[ACCIÓN] Click paso 04 → Enter`

> Corchete, corchete. Lista vacía. HTTP 200.
>
> Y acá está la parte más fea de todas: **una lista vacía es una respuesta
> normal**. Es exactamente lo que devolvería una app recién desplegada
> a la que nadie le preguntó nada todavía.
>
> Si yo tuviera un dashboard contando consultas guardadas, marcaría cero.
> Y cero no es un error. Cero no dispara ninguna alerta.

`[PAUSA]`

> Esto no es un log. No es una métrica de infraestructura. No es un Event.
> Son **datos de negocio** — y es la única capa donde este problema es
> visible desde afuera.

### Paso 05 — la única verdad (~1 min)

> Nos queda un lugar. Preguntarle a la aplicación.

`[ACCIÓN] Click paso 05 → Enter`

> Ahí está. `could not log query to MongoDB: Connection refused`.
>
> Una cosa del comando: fíjense que uso `-l` con la label y `--prefix`,
> no `logs deploy/`. Tengo dos réplicas. Si pido los logs del Deployment,
> kubectl elige **una** — y la línea que busco puede estar en la otra.
> Con `-l` las junta todas y me dice de qué Pod viene cada una.

`[ACCIÓN] Señalar dos líneas seguidas en pantalla]`

> Y miren estas dos líneas juntas, una arriba de la otra:
>
> El error de Mongo. Y justo abajo: `POST /ask 200 OK`.
>
> Esa es toda la historia en dos renglones.

### Cierre (~1 min)

> Recapitulemos los tres.
>
> Bug 1: capa de Pod. La evidencia estaba en los **Events**, y los logs
> no servían para nada.
>
> Bug 2: capa de Service. Los Pods estaban perfectos, la evidencia
> estaba en los **Endpoints**.
>
> Bug 3: la base de datos. Kubernetes nos dice que está todo bien.
> Y está todo bien — desde donde Kubernetes mira.
>
> La evidencia estaba en los logs de la aplicación y en los datos.

`[PAUSA]`

> De los tres, este es el único que no le llega a nadie.
> El primero lo ve el que hizo el deploy. El segundo lo ven los usuarios
> a los treinta segundos.
>
> Este puede estar corriendo una semana.
>
> Y por eso instalamos Prometheus hace veinte minutos. Porque este
> problema no se ve como un Pod rojo — se ve como una métrica de negocio
> que se aplana. Y eso solo lo ves si lo estás midiendo.

### Reparar

`[ACCIÓN] Click paso 06 → Enter`

> Lo devolvemos.
>
> Y si vuelvo a pedir el health, ahora sí: `"database": "ok"`.

---

## Si algo sale mal

**El `/ask` tarda o falla:** el timeout de Mongo es 1.5s, así que la
primera request después de bajar la base puede demorar. Pedila de nuevo.

**El paso 05 no muestra nada:** faltan las preguntas de la slide 16.
Volvé, preguntá 2–3 veces, y repetí el paso.

**Mongo no vuelve:** el volumen EBS es RWO y el Deployment usa
`strategy: Recreate`. Si el Pod queda en Pending, esperá — se está
re-adjuntando el volumen. `kubectl -n session-5 describe pod -l app=mongo`
lo confirma en los Events.

## Frases para tener a mano

- "Un probe verifica lo que le dijiste que verifique, no lo que querías decir."
- "Cero no es un error. Cero no despierta a nadie."
- "Kubernetes dice que está sano. Y tiene razón, desde donde él mira."
- "Este es el bug que no le llega a nadie."
