defmodule LcdDisplay.MixProject do
  use Mix.Project

  @version "0.0.13"
  @source_url "https://github.com/mnishiguchi/lcd_display"

  def project do
    [
      app: :lcd_display,
      version: @version,
      elixir: "~> 1.11",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      build_embedded: Mix.env() == :prod,
      description: "Control an Liquid-crystal display (LCD) like Hitachi HD44780",
      deps: deps(),
      docs: docs(),
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {LcdDisplay.Application, []}
    ]
  end

  # ensure test/support is compiled
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_gpio, "~> 0.4"},
      {:circuits_i2c, "~> 0.1"},
      {:mox, "~> 1.0.0", only: :test},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false},
      {:ex_doc, "~> 0.14", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end

  defp package do
    %{
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE*"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Hitachi HD44780 datasheet" => "https://cdn-shop.adafruit.com/datasheets/HD44780.pdf"
      }
    }
  end
end
