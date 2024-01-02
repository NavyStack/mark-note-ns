FROM node:20-bookworm as upstream-donwloader
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
ENV PATH="/root/.cargo/bin:${PNPM_HOME}:${PATH}"
RUN corepack enable

WORKDIR /upstream-donwloader
RUN git clone --recurse-submodules -j8 https://github.com/enchant97/note-mark.git . \
    && cd /upstream-donwloader/frontend \
    && pnpm import \
    && pnpm install binaryen@116.0.0 @codemirror/commands@6.3.3 workbox-window@7.0.0

FROM golang:1.21 as backend
RUN apt update \
    && apt install -y tini
WORKDIR /backend-build

COPY --from=upstream-donwloader /upstream-donwloader/backend/go.mod /upstream-donwloader/backend/go.sum /backend-build/
RUN go mod download \
    && go mod verify

COPY --from=upstream-donwloader /upstream-donwloader/backend .
RUN CGO_ENABLED=0 go build -o /backend-build/note-mark

FROM node:20-bookworm as frontend
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
ENV PATH="/root/.cargo/bin:${PNPM_HOME}:${PATH}"
RUN corepack enable

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
# RUN curl https://rustwasm.github.io/wasm-pack/installer/init.sh -sSf | sh -s -- -y
WORKDIR /frontend-build

# COPY --from=upstream-donwloader /upstream-donwloader/frontend/package.json /upstream-donwloader/frontend/pnpm-lock.yaml /frontend-build/
COPY --link --from=upstream-donwloader /upstream-donwloader/frontend/node_modules /frontend-build/node_modules/
# RUN pnpm install # --frozen-lockfile --prod
COPY --from=upstream-donwloader /upstream-donwloader/frontend .
RUN pnpm run wasm
RUN pnpm run build

FROM debian:bookworm-slim AS FINAL
ARG USER=note-mark
RUN useradd -d /app --shell /bin/bash $USER \
    && mkdir -p /app/data && chown $USER:$USER /app/data
USER $USER

WORKDIR /app
COPY --from=frontend --chown=$USER:$USER /frontend-build/dist /app/web/
COPY --from=backend --chown=$USER:$USER /backend-build/note-mark /usr/bin/tini /usr/local/bin/

ENV BIND__HOST=0.0.0.0 \
    BIND__PORT=8000 \
    DB__URI=/app/data/db.sqlite \
    DB__TYPE=sqlite \
    DATA_PATH=/app/data \
    STATIC_PATH=/app/web

EXPOSE 8000/tcp

VOLUME /app/data
ENTRYPOINT [ "tini", "--", "note-mark", "serve" ]
