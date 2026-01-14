
FROM elixir:latest

# Set environment to production
ENV MIX_ENV=prod

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy configuration files first
COPY mix.exs mix.lock ./

# Fetch dependencies
RUN mix deps.get
RUN mix deps.compile

# Copy application code
COPY lib ./lib
COPY cities.yaml ./

# Compile the application
RUN mix compile

# Create the output directory
RUN mkdir -p doc

# Command to run the application
CMD ["mix", "run", "-e", "WeatherGen.App.run()"]
