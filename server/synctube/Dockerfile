# SyncTube, built in two stages.
# Stage 1 is the author's own recipe: Haxe turns the source code into JavaScript.
# Stage 2 copies only the finished app into the official Node.js image, pinned to an exact
# patched version, so we choose the Node.js that runs it (not whatever Alpine happens to ship).
# The source code comes from the "synctube-src" context in docker-compose.yml (one pinned commit).

FROM haxe:4.3-alpine3.22 AS build
RUN apk add --no-cache nodejs npm git
RUN addgroup -g 1000 app && adduser -u 1000 -G app -s /bin/sh -D app && mkdir /app && chown app:app /app
WORKDIR /app
USER 1000
COPY --from=synctube-src --chown=app:app / ./
RUN npm ci
RUN haxelib setup /app \
    && haxelib install all --always \
    && haxe build-all.hxml

# Node.js 22.23.4 fixes the October 2026 security releases (nodejs.org/en/blog/vulnerability).
# To update Node.js later: change the version below, then `docker compose up -d --build synctube`.
FROM node:22.23.4-alpine3.23
WORKDIR /app
# The node image already has user "node" with ID 1000, the owner of ${CONFIG_DIR}/synctube.
COPY --from=build --chown=node:node /app/build ./build
COPY --from=build --chown=node:node /app/res ./res
COPY --from=build --chown=node:node /app/user ./user
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/default-config.json /app/package.json ./
USER node
EXPOSE 4200
ENTRYPOINT ["node", "build/server.js"]
