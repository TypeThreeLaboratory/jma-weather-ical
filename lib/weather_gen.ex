defmodule WeatherGen do
  @moduledoc """
  WeatherGenアプリケーションのメインモジュール。
  """

  @doc """
  アプリケーションのエントリポイント。
  必要なアプリケーション（:weather_gen）を起動し、メイン処理を実行する。
  """
  def main(_args \\ []) do
    Application.ensure_all_started(:weather_gen)
    WeatherGen.App.run()
  end

  defmodule Config do
    require Logger

    def load(file \\ "cities.yaml") do
      case YamlElixir.read_from_file(file) do
        {:ok, content} ->
          content
        {:error, reason} ->
          Logger.error("Config file '#{file}' not found or readable: #{inspect(reason)}")
          %{}
      end
    end
  end

  defmodule Fetcher do
    require Logger

    @base_url "https://www.jma.go.jp/bosai/forecast/data/forecast"

    def fetch(area_code) do
      url = "#{@base_url}/#{area_code}.json"
      case Req.get(url) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          body
        {:ok, %Req.Response{status: status}} ->
          Logger.error("Error fetching data for #{area_code}: HTTP #{status}")
          nil
        {:error, exception} ->
          Logger.error("Error fetching data for #{area_code}: #{inspect(exception)}")
          nil
      end
    end
  end

  defmodule Event do
    defstruct [:start_date, :summary, :description]
  end

  defmodule ICS do
    def generate(events) do
      dtstamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")

      events_content = Enum.map(events, fn evt ->
        """
        BEGIN:VEVENT
        UID:#{UUID.uuid4()}
        DTSTAMP:#{dtstamp}
        DTSTART;VALUE=DATE:#{evt.start_date}
        SUMMARY:#{evt.summary}
        DESCRIPTION:#{evt.description}
        END:VEVENT
        """
        |> String.trim()
      end)
      |> Enum.join("\r\n")

      """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:-//JMA Weather Gen//EN
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      X-WR-CALNAME:JMA Forecast
      X-WR-TIMEZONE:Asia/Tokyo
      #{events_content}
      END:VCALENDAR
      """
      |> String.trim()
      |> String.replace("\n", "\r\n")
    end
  end

  defmodule App do
    require Logger

    def run(output_dir \\ "dist") do
      cities = WeatherGen.Config.load()

      if cities == %{} do
        Logger.warning("No cities found in config. Exiting.")
      else
        for {city, code} <- cities do
          Logger.info("Processing #{city} (#{code})...")
          with data when not is_nil(data) <- WeatherGen.Fetcher.fetch(code),
               events <- parse_weather_data(city, data),
               false <- Enum.empty?(events) do

            ics_content = WeatherGen.ICS.generate(events)
            save_ics(city, ics_content, output_dir)
          else
            nil -> :ok # 取得失敗。ログ出力済み。
            true -> Logger.warning("#{city} のイベントを解析できませんでした。") # Enum.empty?(events) が true の場合
            _ -> :ok
          end
        end
      end
    end

    @weather_codes %{
      "100" => "晴れ",
      "101" => "晴れ時々くもり",
      "102" => "晴れ一時雨",
      "104" => "晴れ時々雪",
      "110" => "時々晴れ",
      "111" => "くもり時々晴れ",
      "112" => "くもり一時雨",
      "114" => "くもり一時雪",
      "200" => "くもり",
      "201" => "くもり時々晴れ",
      "202" => "くもり一時雨",
      "204" => "くもり一時雪",
      "210" => "くもり後晴れ",
      "211" => "くもり後晴れ",
      "212" => "くもり後雨",
      "214" => "くもり後雪",
      "300" => "雨",
      "301" => "雨時々晴れ",
      "302" => "雨時々くもり",
      "303" => "雨一時雪",
      "400" => "雪",
      "401" => "雪時々晴れ",
      "402" => "雪時々くもり",
      "403" => "雪一時雨"
    }

    defp parse_weather_data(city_name, weather_data) do
      weather_data
      |> Enum.flat_map(fn report ->
        time_series = report["timeSeries"] || []

        Enum.at(time_series, 0, %{})
        |> extract_events(city_name)
      end)
      |> Enum.reduce(%{}, fn event, acc ->
        # 同一日の予報がある場合、より詳細な情報（weathersがある方など）を持つものを優先したいが、
        # 配列の順序的に短期予報が先に来るため、既存の値を優先する。
        Map.put_new(acc, event.start_date, event)
      end)
      |> Map.values()
      |> Enum.sort_by(& &1.start_date)
    end

    defp extract_events(%{"timeDefines" => time_defines, "areas" => areas}, city_name)
         when is_list(time_defines) and is_list(areas) do
      area_data = Enum.at(areas, 0, %{})
      weathers = area_data["weathers"]
      weather_codes = area_data["weatherCodes"]

      time_defines
      |> Enum.with_index()
      |> Enum.map(fn {time_str, i} ->
        date_str = time_str |> String.slice(0, 10) |> String.replace("-", "")

        weather_text =
          cond do
            weathers && Enum.at(weathers, i) ->
              Enum.at(weathers, i) |> String.replace("\u3000", " ")

            weather_codes && Enum.at(weather_codes, i) ->
              code = Enum.at(weather_codes, i)
              Map.get(@weather_codes, code, "不明(#{code})")

            true ->
              "情報なし"
          end

        %WeatherGen.Event{
          start_date: date_str,
          summary: "#{city_name}: #{weather_text}",
          description: "#{weather_text}\n出典: 気象庁"
        }
      end)
    end

    defp extract_events(_, _), do: []

    defp save_ics(city_name, content, output_dir) do
      File.mkdir_p!(output_dir)
      filename = Path.join(output_dir, "#{city_name}.ics")
      case File.write(filename, content) do
        :ok -> Logger.info("Generated #{filename}")
        {:error, reason} -> Logger.error("Failed to write file #{filename}: #{inspect(reason)}")
      end
    end
  end
end
