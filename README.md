# jma-weather-ical

気象庁データの取得およびiCalendar形式への変換

## 必要なもの

- Docker (推奨)
- または Elixir (ローカル実行用)

## 実行手順 (Docker)

環境構築不要で実行できます。

1. **Dockerイメージのビルド**

   ```bash
   docker build -t jma-weather .
   ```

2. **アプリケーションの実行とデータ取得**

   ```bash
   # コンテナを実行 (データ生成)
   docker run --name jma-gen jma-weather

   # 生成されたデータをホストの doc ディレクトリにコピー
   # (既存の doc ディレクトリがある場合は上書きされます)
   docker cp jma-gen:/app/doc .

   # コンテナの削除
   docker rm jma-gen
   ```

   `doc` ディレクトリに `.ics` ファイルが生成されます。

## 実行手順 (ローカル Elixir 環境)

1. **依存関係のインストール**

   ```bash
   mix deps.get
   ```

2. **アプリケーションの実行**

   ```bash
   mix run -e 'WeatherGen.App.run()'
   ```

   `cities.yaml` の設定に基づいて気象データを取得し、`doc` ディレクトリに `.ics` ファイルが生成されます。
