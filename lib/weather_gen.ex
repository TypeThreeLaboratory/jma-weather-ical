defmodule WeatherGen do
  @moduledoc """
  Main module for WeatherGen application.
  """

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

    def run(output_dir \\ "doc") do
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
            nil -> :ok # Fetch failed, already logged
            true -> Logger.warning("No events parsed for #{city}") # Enum.empty?(events) is true
            _ -> :ok
          end
        end
      end
    end

    defp parse_weather_data(city_name, weather_data) do
      try do
        report = Enum.at(weather_data, 0)
        time_series = report["timeSeries"]
        
        if is_nil(time_series) or Enum.empty?(time_series) do
          []
        else
          weather_series = Enum.at(time_series, 0)
          time_defines = weather_series["timeDefines"]
          areas = weather_series["areas"]

          if is_nil(areas) or Enum.empty?(areas) do
            []
          else
            area_weather = Enum.at(areas, 0)
            weathers = area_weather["weathers"]

            time_defines
            |> Enum.with_index()
            |> Enum.map(fn {time_str, i} ->
              # JMA returns ISO string e.g. "2023-10-27T17:00:00+09:00"
              # We just want the date part "20231027"
              date_str = 
                time_str
                |> String.slice(0, 10)
                |> String.replace("-", "")

              weather_text = 
                if i < length(weathers) do
                  Enum.at(weathers, i) |> String.replace("\u3000", " ")
                else
                  "No Data"
                end
              
              summary = weather_text
              description = "#{weather_text}\nSource: JMA"
              
              %WeatherGen.Event{
                start_date: date_str,
                summary: "#{city_name}: #{summary}",
                description: description
              }
            end)
          end
        end
      rescue
        _ -> []
      end
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
