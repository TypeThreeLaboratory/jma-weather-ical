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

    def run(output_dir \\ "dist") do
      cities = WeatherGen.Config.load()

      if cities == %{} do
        Logger.warning("No cities found in config. Exiting.")
      else
        for {city, code} <- cities do
          Logger.info("Processing #{city} (#{code})...")
          with data when not is_nil(data) <- WeatherGen.Fetcher.fetch(code),
               events <- process_weather_data(city, data),
               false <- Enum.empty?(events) do
            ics_content = WeatherGen.ICS.generate(events)
            save_ics(city, ics_content, output_dir)
          else
            nil -> :ok
            true -> Logger.warning("#{city} のイベントを解析できませんでした。")
            _ -> :ok
          end
        end
      end
    end

    defp process_weather_data(city_name, weather_data) do
      # 全てのタイムシリーズデータを日付ごとに集約する
      weather_data
      |> Enum.flat_map(fn report -> report["timeSeries"] || [] end)
      |> Enum.reduce(%{}, fn series, acc ->
        merge_series_data(acc, series)
      end)
      |> Map.values()
      |> Enum.sort_by(& &1.date)
      |> Enum.map(&format_event(&1, city_name))
    end

    defp merge_series_data(acc, %{"timeDefines" => time_defines, "areas" => areas})
         when is_list(time_defines) and is_list(areas) do
      # 指定エリア(リストの先頭)のデータを取得
      area_data = Enum.at(areas, 0, %{})

      # データの種類を判定
      has_weathers = Map.has_key?(area_data, "weathers")
      has_codes = Map.has_key?(area_data, "weatherCodes")
      has_pops = Map.has_key?(area_data, "pops")
      has_temps_min = Map.has_key?(area_data, "tempsMin")
      has_temps_max = Map.has_key?(area_data, "tempsMax")

      time_defines
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {time_str, i}, map ->
        date = parse_date(time_str)
        current = Map.get(map, date, %{date: date, weather: nil, pop: nil, min: nil, max: nil})

        updated =
          current
          |> update_weather(has_weathers, has_codes, area_data, i)
          |> update_pop(has_pops, area_data, i)
          |> update_temps(has_temps_min, has_temps_max, area_data, i)

        Map.put(map, date, updated)
      end)
    end

    defp merge_series_data(acc, _), do: acc

    defp parse_date(iso_string) do
      case DateTime.from_iso8601(iso_string) do
        {:ok, dt, _offset} -> DateTime.to_date(dt)
        _ ->
          # 失敗時は文字列の先頭10桁を使う簡易対応
          Date.from_iso8601!(String.slice(iso_string, 0, 10))
      end
    end

    defp update_weather(data, true, _, area, i) do
       # 天気テキストがあれば優先して設定、ただし既存のテキストがある場合は(詳細なReport0を維持するために)上書きしない判断も可能だが
       # Report0(詳細) -> Report1(コードのみ) の順の場合、詳細を残したい。
       # JMAのJSONはリスト順なので通常 Report0 が先。
       # したがって、既に値がある場合は上書きしない、または明示的に詳細な方を優先するロジックにする。
       # ここでは「nilなら設定」とする。
       if data.weather == nil do
         %{data | weather: Enum.at(area["weathers"], i) |> String.replace("\u3000", " ") }
       else
         data
       end
    end
    defp update_weather(data, _, true, area, i) do
      # 天気コードからの変換
      if data.weather == nil do
        code = Enum.at(area["weatherCodes"], i)
        text = Map.get(@weather_codes, code, "不明(#{code})")
        %{data | weather: text}
      else
        data
      end
    end
    defp update_weather(data, _, _, _, _), do: data

    defp update_pop(data, true, area, i) do
      pop_str = Enum.at(area["pops"], i)
      case Integer.parse(pop_str || "") do
        {val, _} ->
          # 降水確率は最大値を採用する
          current_pop = data.pop || 0
          %{data | pop: max(current_pop, val)}
        :error -> data
      end
    end
    defp update_pop(data, _, _, _), do: data

    defp update_temps(data, true, _, area, i) do
      min = Enum.at(area["tempsMin"], i)
      if min != "" and min != nil, do: %{data | min: min}, else: data
    end
    defp update_temps(data, _, true, area, i) do
      max = Enum.at(area["tempsMax"], i)
      if max != "" and max != nil, do: %{data | max: max}, else: data
    end
    defp update_temps(data, _, _, _, _), do: data


    defp format_event(day_data, city_name) do
      day_str = "#{day_data.date.month}月 #{day_data.date.day}日 (#{day_of_week_jp(day_data.date)})"

      weather_text = day_data.weather || "情報なし"
      pop_text = if day_data.pop, do: "#{day_data.pop}%", else: "---"
      min_text = day_data.min || "-"
      max_text = day_data.max || "-"

      summary_temp = "#{max_text}°C/#{min_text}°C"

      # サマリー形式: 天気 最高/最低
      summary = "#{weather_text} #{summary_temp}"

      # 詳細文を作成
      description = "天気は#{weather_text}、降水確率は#{pop_text}、最高気温は#{max_text}°C、最低気温は#{min_text}°Cでしょう。"

      %WeatherGen.Event{
        start_date: String.replace(Date.to_string(day_data.date), "-", ""),
        summary: summary,
        description: "#{description}\n出典: 気象庁"
      }
    end

    defp day_of_week_jp(date) do
      days = %{1 => "月", 2 => "火", 3 => "水", 4 => "木", 5 => "金", 6 => "土", 7 => "日"}
      Map.get(days, Date.day_of_week(date), "")
    end

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
