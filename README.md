# jma-weather-ical

気象庁データの取得およびiCalendar形式への変換

## 必要なもの

- Docker

## 実行手順

環境構築不要で実行できます。

1. **Dockerイメージのビルド**

   ```bash
   docker build -t jma-weather-gen .
   ```

2. **アプリケーションの実行とデータ取得**

   ```bash
   # コンテナを実行してデータを作成
   docker run --name jma-weather-gen jma-weather-gen:latest

   # コンテナから生成されたデータをコピー
   docker cp jma-weather-gen:/app/dist ./dist

   # 使用済みコンテナの削除
   docker rm jma-weather-gen
   ```

   `dist` ディレクトリに `.ics` ファイルが生成されます。
