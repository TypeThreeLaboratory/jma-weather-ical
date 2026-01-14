# Build Stage
FROM elixir:1.15-alpine AS builder

# 環境をプロダクションに設定
ENV MIX_ENV=prod
# QEMU(ARM64)でのビルドクラッシュを防ぐため、スケジューラをシングルスレッドに制限
ENV ERL_FLAGS="+S 1"

WORKDIR /app

# ビルドに必要なツールをインストール
RUN apk add --no-cache build-base git

# Hex と Rebar をインストール
RUN mix local.hex --force && \
    mix local.rebar --force

# 設定ファイルを先にコピー
COPY mix.exs mix.lock ./

# 依存関係の取得とコンパイル
RUN mix deps.get --only prod
RUN mix deps.compile

# アプリケーションコードと設定をコピー
COPY lib ./lib
COPY config ./config
COPY cities.yaml ./

# リリースの作成
RUN mix compile
RUN mix release

# 実行用のラッパースクリプトを作成
RUN echo '#!/bin/sh' > WeatherGen && \
    echo 'exec /app/bin/weather_gen eval "WeatherGen.main()"' >> WeatherGen && \
    chmod +x WeatherGen

# Runtime Stage
FROM alpine:latest AS runtime

# 実行に必要なランタイムライブラリをインストール
RUN apk add --no-cache libstdc++ ncurses-libs openssl libgcc

WORKDIR /app

# ビルドステージからリリースと設定ファイルをコピー
COPY --from=builder /app/_build/prod/rel/weather_gen ./
COPY --from=builder /app/cities.yaml ./
COPY --from=builder /app/WeatherGen ./

# 実行コマンドの設定
# ラッパースクリプトを直接実行する形式に変更
CMD ["./WeatherGen"]
