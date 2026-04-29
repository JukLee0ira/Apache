FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    lua5.1 \
    lua-cjson \
    lua-socket \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY mock_rpc.lua /app/mock_rpc.lua

EXPOSE 8545
CMD ["lua5.1", "/app/mock_rpc.lua"]
