# --- build stage ---
FROM node:20-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

# --- serve stage ---
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html

# Rendered at container startup (envsubst-on-templates, built into this
# base image) into /etc/nginx/conf.d/default.conf. API_UPSTREAM is a
# runtime env var, not a build arg - the same image works unchanged in
# docker-compose (API_UPSTREAM=api:8000) and in Kubernetes
# (API_UPSTREAM=api-spacy-finance:80).
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
ENV API_UPSTREAM=localhost:8000

EXPOSE 80
