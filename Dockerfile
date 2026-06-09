FROM golang:alpine AS builder
WORKDIR /app
COPY . .
ARG GITHUB_SHA
ARG VERSION
RUN apk add --no-cache nodejs zstd && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
        "x86_64") zstd -f /usr/bin/node -o assets/node_linux_amd64.zst ;; \
        "aarch64") zstd -f /usr/bin/node -o assets/node_linux_arm64.zst ;; \
        "armv7l") zstd -f /usr/bin/node -o assets/node_linux_armv7.zst ;; \
        *) echo "不支持的架构: $ARCH" && exit 1 ;; \
    esac
RUN echo "Building commit: ${GITHUB_SHA:0:7}" && \
    go mod tidy && \
    go build -ldflags="-s -w -X main.Version=${VERSION} -X main.CurrentCommit=${GITHUB_SHA:0:7}" -trimpath -o subs-check .

FROM alpine
WORKDIR /app
ENV TZ=Asia/Shanghai
RUN apk add --no-cache alpine-conf ca-certificates nodejs &&\
    /usr/sbin/setup-timezone -z Asia/Shanghai && \
    apk del alpine-conf && \
    rm -rf /var/cache/apk/* && \
    rm -rf /usr/bin/node
COPY --from=builder /app/subs-check /app/subs-check

# 1. 复制配置文件
COPY --from=builder /app/config/config.example.yaml /app/config/config.yaml

# 2. 动态调优：绑定 Render 端口 + 降低内存消耗防崩溃
CMD sed -i "s|save-method:.*|save-method: gist|g" /app/config/config.yaml && \
    sed -i "s|github-gist-id:.*|github-gist-id: \"$GIST_ID\"|g" /app/config/config.yaml && \
    sed -i "s|github-token:.*|github-token: \"$GIST_TOKEN\"|g" /app/config/config.yaml && \
    sed -i "s|listen-port:.*|listen-port: \":$PORT\"|g" /app/config/config.yaml && \
    sed -i "s|concurrent:.*|concurrent: 100|g" /app/config/config.yaml && \
    sed -i "s|speed-concurrent:.*|speed-concurrent: 3|g" /app/config/config.yaml && \
    sed -i "s|download-mb:.*|download-mb: 5|g" /app/config/config.yaml && \
    /app/subs-check

# 这里的 EXPOSE 没用了，Render 认的是环境变量 $PORT
