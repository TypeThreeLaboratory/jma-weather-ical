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



  defmodule ICS do
    def generate(events, city_name_en, city_name_jp) do
      dtstamp = DateTime.utc_now() |> Calendar.strftime("%Y%m%dT%H%M%SZ")

      events_content = Enum.map(events, fn evt ->
        """
        BEGIN:VEVENT
        UID:#{evt.uid}
        DESCRIPTION:#{evt.description}
        DTSTART:#{evt.start_date}
        DTEND:#{evt.end_date}
        SUMMARY:#{evt.summary}
        END:VEVENT
        """
        |> String.trim()
      end)
      |> Enum.join("\n")

      """
      BEGIN:VCALENDAR
      VERSION:2.0
      PRODID:jma-weather-ical
      CALSCALE:GREGORIAN
      METHOD:PUBLISH
      X-WR-CALNAME:週間天気予報 #{city_name_jp}
      X-WR-TIMEZONE:Asia/Tokyo
      #{events_content}
      BEGIN:VTIMEZONE
      TZID:Asia/Tokyo
      BEGIN:STANDARD
      DTSTART:19700101T000000
      TZOFFSETFROM:+0900
      TZOFFSETTO:+0900
      END:STANDARD
      END:VTIMEZONE
      END:VCALENDAR
      """
      |> String.trim()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.join("\r\n")
    end
  end

  defmodule App do
    require Logger

    @weather_codes %{
      "100" => "晴れ",
      "101" => "晴れ時々くもり",
      "102" => "晴れ一時雨",
      "103" => "晴れ時々雨",
      "104" => "晴れ一時雪",
      "105" => "晴れ時々雪",
      "106" => "晴れ一時雨か雪",
      "107" => "晴れ時々雨か雪",
      "108" => "晴れ一時雨か雷雨",
      "110" => "晴れのち時々くもり",
      "111" => "晴れのちくもり",
      "112" => "晴れのち一時雨",
      "113" => "晴れのち時々雨",
      "114" => "晴れのち雨",
      "115" => "晴れのち一時雪",
      "116" => "晴れのち時々雪",
      "117" => "晴れのち雪",
      "118" => "晴れのち雨か雪",
      "119" => "晴れのち雨か雷雨",
      "120" => "晴れ朝夕一時雨",
      "121" => "晴れ朝の内一時雨",
      "122" => "晴れ夕方一時雨",
      "123" => "晴れ山沿い雷雨",
      "124" => "晴れ山沿い雪",
      "125" => "晴れ午後は雷雨",
      "126" => "晴れ昼頃から雨",
      "127" => "晴れ夕方から雨",
      "128" => "晴れ夜は雨",
      "129" => "晴れ夜半から雨",
      "130" => "朝の内霧後晴れ",
      "131" => "晴れ明け方霧",
      "132" => "晴れ朝夕くもり",
      "140" => "晴れ時々雨で雷を伴う",
      "160" => "晴れ一時雪か雨",
      "170" => "晴れ時々雪か雨",
      "181" => "晴れのち雪か雨",
      "200" => "くもり",
      "201" => "くもり時々晴",
      "202" => "くもり一時雨",
      "203" => "くもり時々雨",
      "204" => "くもり一時雪",
      "205" => "くもり時々雪",
      "206" => "くもり一時雨か雪",
      "207" => "くもり時々雨か雪",
      "208" => "くもり一時雨か雷雨",
      "209" => "霧",
      "210" => "くもりのち時々晴れ",
      "211" => "くもりのち晴れ",
      "212" => "くもりのち一時雨",
      "213" => "くもりのち時々雨",
      "214" => "くもりのち雨",
      "215" => "くもりのち一時雪",
      "216" => "くもりのち時々雪",
      "217" => "くもりのち雪",
      "218" => "くもりのち雨か雪",
      "219" => "くもりのち雨か雷雨",
      "220" => "くもり朝夕一時雨",
      "221" => "くもり朝の内一時雨",
      "222" => "くもり夕方一時雨",
      "223" => "くもり日中時々晴れ",
      "224" => "くもり昼頃から雨",
      "225" => "くもり夕方から雨",
      "226" => "くもり夜は雨",
      "227" => "くもり夜半から雨",
      "228" => "くもり昼頃から雪",
      "229" => "くもり夕方から雪",
      "230" => "くもり夜は雪",
      "231" => "くもり海上海岸は霧か霧雨",
      "240" => "くもり時々雨で雷を伴う",
      "250" => "くもり時々雪で雷を伴う",
      "260" => "くもり一時雪か雨",
      "270" => "くもり時々雪か雨",
      "281" => "くもりのち雪か雨",
      "300" => "雨",
      "301" => "雨時々晴れ",
      "302" => "雨時々止む",
      "303" => "雨時々雪",
      "304" => "雨か雪",
      "306" => "大雨",
      "307" => "風雨共に強い",
      "308" => "雨で暴風を伴う",
      "309" => "雨一時雪",
      "311" => "雨のち晴れ",
      "313" => "雨のちくもり",
      "314" => "雨のち時々雪",
      "315" => "雨のち雪",
      "316" => "雨か雪のち晴れ",
      "317" => "雨か雪のちくもり",
      "320" => "朝の内雨のち晴れ",
      "321" => "朝の内雨のちくもり",
      "322" => "雨朝晩一時雪",
      "323" => "雨昼頃から晴れ",
      "324" => "雨夕方から晴れ",
      "325" => "雨夜は晴",
      "326" => "雨夕方から雪",
      "327" => "雨夜は雪",
      "328" => "雨一時強く降る",
      "329" => "雨一時みぞれ",
      "340" => "雪か雨",
      "350" => "雨で雷を伴う",
      "361" => "雪か雨のち晴れ",
      "371" => "雪か雨のちくもり",
      "400" => "雪",
      "401" => "雪時々晴れ",
      "402" => "雪時々止む",
      "403" => "雪時々雨",
      "405" => "大雪",
      "406" => "風雪強い",
      "407" => "暴風雪",
      "409" => "雪一時雨",
      "411" => "雪のち晴れ",
      "413" => "雪のちくもり",
      "414" => "雪のち雨",
      "420" => "朝の内雪のち晴れ",
      "421" => "朝の内雪のちくもり",
      "422" => "雪昼頃から雨",
      "423" => "雪夕方から雨",
      "424" => "雪夜半から雨",
      "425" => "雪一時強く降る",
      "426" => "雪のちみぞれ",
      "427" => "雪一時みぞれ",
      "450" => "雪で雷を伴う"
    }

    def run(output_dir \\ "dist") do
      cities = WeatherGen.Config.load()

      if cities == %{} do
        Logger.warning("No cities found in config. Exiting.")
      else
        for {city_en, code} <- cities do
          Logger.info("Processing #{city_en} (#{code})...")
          with data when not is_nil(data) <- WeatherGen.Fetcher.fetch(code),
               events <- process_weather_data(city_en, data),
               false <- Enum.empty?(events) do
            city_jp = extract_city_jp(data) || city_en
            ics_content = WeatherGen.ICS.generate(events, city_en, city_jp)
            save_ics(city_en, ics_content, output_dir)
          else
            nil -> :ok
            true -> Logger.warning("#{city_en} のイベントを解析できませんでした。")
            _ -> :ok
          end
        end
        # Generate index.html after processing all cities
        generate_index_html(output_dir, cities)
        # Generate robots.txt
        generate_robots_txt(output_dir)
        # Generate favicon.svg
        generate_favicon(output_dir)
      end
    end

    defp generate_robots_txt(output_dir) do
      content = """
      User-agent: *
      Allow: /
      """
      
      File.mkdir_p!(output_dir)
      filename = Path.join(output_dir, "robots.txt")
      case File.write(filename, content) do
        :ok -> Logger.info("Generated #{filename}")
        {:error, reason} -> Logger.error("Failed to write file #{filename}: #{inspect(reason)}")
      end
    end

    defp generate_favicon(output_dir) do
      # Simple sun icon SVG
      content = """
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <circle cx="50" cy="50" r="25" fill="#FFA500" />
        <g stroke="#FFA500" stroke-width="8" stroke-linecap="round">
          <line x1="50" y1="10" x2="50" y2="18" />
          <line x1="50" y1="82" x2="50" y2="90" />
          <line x1="90" y1="50" x2="82" y2="50" />
          <line x1="10" y1="50" x2="18" y2="50" />
          <line x1="78.3" y1="21.7" x2="72.6" y2="27.4" />
          <line x1="27.4" y1="72.6" x2="21.7" y2="78.3" />
          <line x1="78.3" y1="78.3" x2="72.6" y2="72.6" />
          <line x1="27.4" y1="27.4" x2="21.7" y2="21.7" />
        </g>
      </svg>
      """
      
      File.mkdir_p!(output_dir)
      filename = Path.join(output_dir, "favicon.svg")
      case File.write(filename, content) do
        :ok -> Logger.info("Generated #{filename}")
        {:error, reason} -> Logger.error("Failed to write file #{filename}: #{inspect(reason)}")
      end
    end

    defp generate_index_html(output_dir, cities) do
      list_items =
        cities
        |> Enum.sort_by(fn {city_en, _} -> city_en end)
        |> Enum.map(fn {city_en, _code} ->
          """
          <li><a href="#{city_en}.ics">#{city_en}</a></li>
          """
        end)
        |> Enum.join("\n")

      html_content = """
      <!DOCTYPE html>
      <html lang="ja">
      <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>JMA Weather iCal - 気象庁天気予報iCalendarデータ</title>
          <meta name="description" content="気象庁の天気予報データをiCalendar形式(.ics)で提供します。GoogleカレンダーやOutlookなどで日本の天気予報を確認できます。">
          <meta name="keywords" content="天気予報, iCalendar, ics, カレンダー, 気象庁, API, 自動更新">
          <link rel="canonical" href="https://jma-weather-ical.marumasa.dev/">
          <link rel="icon" type="image/svg+xml" href="favicon.svg">
          
          <!-- Open Graph / Facebook -->
          <meta property="og:type" content="website">
          <meta property="og:url" content="https://jma-weather-ical.marumasa.dev/">
          <meta property="og:title" content="JMA Weather iCal - 気象庁天気予報iCalendarデータ">
          <meta property="og:description" content="気象庁の天気予報データをiCalendar形式(.ics)で提供します。">
          
          <!-- Twitter -->
          <meta property="twitter:card" content="summary_large_image">
          <meta property="twitter:title" content="JMA Weather iCal - 気象庁天気予報iCalendarデータ">
          <meta property="twitter:description" content="気象庁の天気予報データをiCalendar形式(.ics)で提供します。">

          <style>
              body { font-family: "Helvetica Neue", Arial, "Hiragino Kaku Gothic ProN", "Hiragino Sans", Meiryo, sans-serif; margin: 0; padding: 0; line-height: 1.6; color: #333; }
              header { background-color: #f8f9fa; padding: 1rem 2rem; border-bottom: 1px solid #e9ecef; }
              main { padding: 2rem; max-width: 800px; margin: 0 auto; }
              h1 { margin: 0; font-size: 1.5rem; color: #2c3e50; }
              p { margin-bottom: 1.5rem; }
              ul { list-style-type: none; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 10px; }
              li { margin: 0; }
              a { display: block; padding: 0.5rem 1rem; background-color: #e9ecef; border-radius: 4px; text-decoration: none; color: #495057; text-align: center; transition: background-color 0.2s; }
              a:hover { background-color: #dee2e6; text-decoration: none; color: #212529; }
              footer { text-align: center; padding: 2rem; background-color: #f8f9fa; border-top: 1px solid #e9ecef; margin-top: 2rem; font-size: 0.875rem; color: #6c757d; }
          </style>
      </head>
      <body>
          <header>
              <h1>JMA Weather iCal</h1>
          </header>
          <main>
              <p>以下のリンクから、日本各地のiCalendar形式 (.ics) 天気予報データを取得できます。カレンダーアプリに登録してご活用ください。</p>
              <ul>
                  #{list_items}
              </ul>
          </main>
          <footer>
              <p>&copy; #{Date.utc_today().year} JMA Weather iCal. Data source: Japan Meteorological Agency.</p>
          </footer>
      </body>
      </html>
      """

      File.mkdir_p!(output_dir)
      filename = Path.join(output_dir, "index.html")
      case File.write(filename, html_content) do
        :ok -> Logger.info("Generated #{filename}")
        {:error, reason} -> Logger.error("Failed to write file #{filename}: #{inspect(reason)}")
      end
    end

    defp extract_city_jp(weather_data) do
      try do
         weather_data
         |> Enum.at(1) # 週間予報のブロック
         |> Map.get("tempAverage", %{})
         |> Map.get("areas", [])
         |> Enum.at(0)
         |> Map.get("area", %{})
         |> Map.get("name")
      rescue
        _ -> nil
      end
    end

    defp process_weather_data(city_name_en, weather_data) do
      # 現在日時(JST)を取得
      today = DateTime.utc_now() |> DateTime.add(9 * 3600, :second) |> DateTime.to_date()

      # 全てのタイムシリーズデータを日付ごとに集約する
      weather_data
      |> Enum.flat_map(fn report -> report["timeSeries"] || [] end)
      |> Enum.reduce(%{}, fn series, acc ->
        merge_series_data(acc, series)
      end)
      |> Map.values()
      |> Enum.filter(& &1.weather) # 天気情報がない日はスキップ
      |> Enum.filter(&(Date.compare(&1.date, today) != :lt)) # 過去の日付はスキップ
      |> Enum.sort_by(& &1.date)
      |> Enum.map(&format_event(&1, city_name_en, today))
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
        {:ok, dt, _offset} ->
          # JST(UTC+9)の日付として扱うために、UNIX時間に9時間足してから日付を取り出す
          dt
          |> DateTime.to_unix()
          |> Kernel.+(9 * 3600)
          |> DateTime.from_unix!()
          |> DateTime.to_date()
        _ ->
          # 失敗時は文字列の先頭10桁を使う簡易対応
          # 文字列がJST前提であることを仮定
          Date.from_iso8601!(String.slice(iso_string, 0, 10))
      end
    end

    defp update_weather(data, true, _, area, i) do
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

    defp update_temps(data, has_min, has_max, area, i) do
      data
      |> update_temp_min(has_min, area, i)
      |> update_temp_max(has_max, area, i)
    end

    defp update_temp_min(data, true, area, i) do
      min = Enum.at(area["tempsMin"], i)
      if min != "" and min != nil, do: %{data | min: min}, else: data
    end
    defp update_temp_min(data, _, _, _), do: data

    defp update_temp_max(data, true, area, i) do
      max = Enum.at(area["tempsMax"], i)
      if max != "" and max != nil, do: %{data | max: max}, else: data
    end
    defp update_temp_max(data, _, _, _), do: data



    defp format_event(day_data, city_name_en, today) do
      weather_text = day_data.weather || "情報なし"
      
      # 温度の有無チェック
      has_temps = day_data.min != nil and day_data.max != nil
      
      # Summaryの作成
      summary = if day_data.date == today do
        "#{weather_text}"
      else
        if has_temps do
          "#{weather_text} #{day_data.max}℃/#{day_data.min}℃"
        else
          "#{weather_text}"
        end
      end

      # Descriptionの作成
      # 天気は{weather}
      desc_parts = ["天気は#{weather_text}"]
      
      # 降水確率
      desc_parts = if day_data.pop do
        desc_parts ++ ["\\n降水確率は#{day_data.pop}%"]
      else
        desc_parts
      end
      
      # 最高気温
      desc_parts = if day_data.max do
        desc_parts ++ ["\\n最高気温は#{day_data.max}℃"]
      else
        desc_parts
      end
      
      # 最低気温
      desc_parts = if day_data.min do
        desc_parts ++ ["\\n最低気温は#{day_data.min}℃"]
      else
        desc_parts
      end
      
      # 結び
      description = Enum.join(desc_parts, "")

      date_str = String.replace(Date.to_string(day_data.date), "-", "")
      next_day = Date.add(day_data.date, 1) |> Date.to_string() |> String.replace("-", "")
      
      city_lower = String.downcase(city_name_en)

      %{
        uid: "jma-weather-ical-#{city_lower}-#{date_str}",
        start_date: date_str,
        end_date: next_day,
        summary: summary,
        description: description
      }
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
