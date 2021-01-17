defmodule LcdDisplay.GPIO do
  @moduledoc """
  Lets you control GPIOs.
  A thin wrapper of [elixir-circuits/circuits_gpio](https://github.com/elixir-circuits/circuits_gpio).
  """

  defmodule Behaviour do
    @moduledoc """
    Defines a behaviour required for GPIO abstraction.
    """

    @type gpio_pin :: pos_integer

    @callback open(gpio_pin, :output) :: {:ok, reference} | {:error, any}
    @callback write(reference, 0 | 1) :: :ok | {:error, any}
  end

  @behaviour LcdDisplay.GPIO.Behaviour

  def open(gpio_pin, :output), do: gpio_module().open(gpio_pin, :output)

  def write(gpio_ref, 0), do: gpio_module().write(gpio_ref, 0)
  def write(gpio_ref, 1), do: gpio_module().write(gpio_ref, 1)

  defp gpio_module() do
    # https://hexdocs.pm/elixir/master/library-guidelines.html#avoid-compile-time-application-configuration
    Application.get_env(:lcd_display, :gpio_module, Circuits.GPIO)
  end
end
