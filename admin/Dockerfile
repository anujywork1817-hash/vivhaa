# Builds the admin panel and serves the static output with nginx — the
# panel is a Vite/React SPA, so there's no server process to run once it's
# built, just files and a rewrite rule for client-side routing.
FROM node:20-alpine AS build
WORKDIR /app

# Baked in at build time, not runtime: Vite inlines import.meta.env.* into
# the bundle during `vite build`, so the API URL has to be known before the
# build step, not passed to the running container.
ARG VITE_API_BASE_URL
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
