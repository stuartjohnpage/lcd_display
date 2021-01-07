defmodule LcdDisplay.HD44780.I2C do
  @moduledoc """
  Knows how to commuticate with HD44780 type display via I2C.
  You can turn on/off one backlight LED.

  ## Examples

      alias LcdDisplay.HD44780

      config = %{
        display_name: "display 1", # the identifier
        i2c_bus: "i2c-1",          # I2C bus name
        i2c_address: 0x27,         # 7-bit address
        rows: 2,                   # the number of display rows
        cols: 16,                  # the number of display columns
        font_size: "5x8"           # "5x10" or "5x8"
      }

      # Start the LCD driver and get the initial display state.
      {:ok, display} = HD44780.I2C.start(config)

      # Run a command and the display state will be updated.
      {:ok, display} = HD44780.I2C.execute(display, {:print, "Hello world"})
  """

  use Bitwise
  require Logger
  import LcdDisplay.DisplayDriver.Util
  alias LcdDisplay.I2C, as: SerialBus

  @behaviour LcdDisplay.DisplayDriver

  # flags for function set
  @font_size_5x10 0x04
  @font_size_5x8 0x00
  @number_of_lines_2 0x08
  @number_of_lines_1 0x00

  # commands
  @cmd_clear_display 0x01
  @cmd_return_home 0x02
  @cmd_entry_mode_set 0x04
  @cmd_display_control 0x08
  @cmd_cursor_shift_control 0x10
  @cmd_function_set 0x20
  @cmd_set_cgram_address 0x40
  @cmd_set_ddram_address 0x80

  # flags for display entry mode
  @entry_left 0x02
  @autoscroll 0x01

  # flags for display on/off control
  @display_on 0x04
  @cursor_on 0x02
  @blink_on 0x01

  # flags for display/cursor shift
  @shift_display 0x08
  @shift_right 0x04

  # flags for backlight control
  @backlight_on 0x08

  @enable_bit 0b00000100

  @default_i2c_address 0x27
  @default_rows 2
  @default_cols 16

  @typedoc """
  The configuration options.
  """
  @type config :: %{
          optional(:rows) => String.t(),
          optional(:cols) => pos_integer(),
          optional(:font_size) => pos_integer()
        }

  @doc """
  Initializes the LCD driver and returns the initial display state.
  """
  @impl true
  @spec start(config()) :: {:ok, LcdDisplay.DisplayDriver.t()} | {:error, any()}
  def start(config) do
    number_of_lines = if config[:rows] == 1, do: @number_of_lines_1, else: @number_of_lines_2
    font_size = if config[:font_size] == "5x10", do: @font_size_5x10, else: @font_size_5x8

    {:ok,
     config
     |> initial_state()
     |> expander_write(@backlight_on)
     |> initialize_display(function_set: @cmd_function_set ||| font_size ||| number_of_lines)}
  rescue
    e -> {:error, e.message}
  end

  @doc """
  Stops the LCD driver.
  """
  @impl true
  def stop(display) do
    execute(display, {:display, false})
    Circuits.I2C.close(display.i2c_bus)
    :ok
  end

  defp initial_state(opts) do
    i2c_bus = opts[:i2c_bus] || "i2c-1"
    {:ok, i2c_ref} = SerialBus.open(i2c_bus)

    %{
      driver_module: __MODULE__,
      display_name: opts[:display_name] || i2c_bus,
      i2c_ref: i2c_ref,
      i2c_address: opts[:i2c_address] || @default_i2c_address,
      rows: opts[:rows] || @default_rows,
      cols: opts[:cols] || @default_cols,

      # Initial values for features that we can change later.
      entry_mode: @cmd_entry_mode_set ||| @entry_left,
      display_control: @cmd_display_control ||| @display_on,
      backlight: true
    }
  end

  # Initializes the display for 4-bit interface. See Hitachi HD44780 datasheet page 46 for details.
  defp initialize_display(display, function_set: function_set) do
    display
    # Function set (8-bit mode; Interface is 8 bits long)
    |> write_four_bits(0x03)
    |> delay(5)
    |> write_four_bits(0x03)
    |> delay(5)
    |> write_four_bits(0x03)
    |> delay(1)

    # Function set (4-bit mode; Interface is 8 bits long)
    |> write_four_bits(0x02)

    # Function set (4-bit mode; Interface is 4 bits long)
    # The number of display lines and character font cannot be changed after this point.
    |> write_instruction(function_set)
    |> write_feature(:display_control)
    |> clear()
    |> write_feature(:entry_mode)
  end

  @doc """
  Executes the specified command and returns a new display state.
  """
  @impl true
  def execute(display, :clear) do
    clear(display)
    {:ok, display}
  end

  def execute(display, :home) do
    home(display)
    {:ok, display}
  end

  # Write a string.
  def execute(display, {:print, string}) when is_binary(string) do
    # Translates a string to a charlist (list of bytes).
    string |> to_charlist() |> Enum.each(&write_data(display, &1))
    {:ok, display}
  end

  def execute(display, {:set_cursor, row, col}) do
    {:ok, set_cursor(display, row, col)}
  end

  def execute(display, {:cursor, false}) do
    {:ok, disable_display_control_flag(display, @cursor_on)}
  end

  def execute(display, {:cursor, true}) do
    {:ok, enable_display_control_flag(display, @cursor_on)}
  end

  def execute(display, {:blink, false}) do
    {:ok, disable_display_control_flag(display, @blink_on)}
  end

  def execute(display, {:blink, true}) do
    {:ok, enable_display_control_flag(display, @blink_on)}
  end

  def execute(display, {:display, false}) do
    {:ok, disable_display_control_flag(display, @display_on)}
  end

  def execute(display, {:display, true}) do
    {:ok, enable_display_control_flag(display, @display_on)}
  end

  def execute(display, {:autoscroll, false}) do
    {:ok, disable_entry_mode_flag(display, @autoscroll)}
  end

  def execute(display, {:autoscroll, true}) do
    {:ok, enable_entry_mode_flag(display, @autoscroll)}
  end

  def execute(display, {:text_direction, :right_to_left}) do
    {:ok, disable_entry_mode_flag(display, @entry_left)}
  end

  def execute(display, {:text_direction, :left_to_right}) do
    {:ok, enable_entry_mode_flag(display, @entry_left)}
  end

  def execute(display, {:backlight, false}), do: {:ok, set_backlight(display, false)}
  def execute(display, {:backlight, true}), do: {:ok, set_backlight(display, true)}

  def execute(display, {:scroll, 0}), do: {:ok, display}

  # Scroll the entire display left
  def execute(display, {:scroll, cols}) when cols < 0 do
    write_instruction(display, @cmd_cursor_shift_control ||| @shift_display)
    execute(display, {:scroll, cols + 1})
  end

  # Scroll the entire display right
  def execute(display, {:scroll, cols}) when cols > 0 do
    write_instruction(display, @cmd_cursor_shift_control ||| @shift_display ||| @shift_right)
    execute(display, {:scroll, cols - 1})
  end

  # Move cursor right
  def execute(display, {:right, 0}), do: {:ok, display}

  def execute(display, {:right, cols}) do
    write_instruction(display, @cmd_cursor_shift_control ||| @shift_right)
    execute(display, {:right, cols - 1})
  end

  # Move cursor left
  def execute(display, {:left, 0}), do: {:ok, display}

  def execute(display, {:left, cols}) do
    write_instruction(display, @cmd_cursor_shift_control)
    execute(display, {:left, cols - 1})
  end

  # Program custom character to CGRAM. We only have 8 CGRAM locations.
  def execute(display, {:char, index, bitmap}) when index in 0..7 and length(bitmap) === 8 do
    write_instruction(display, @cmd_set_cgram_address ||| index <<< 3)
    for line <- bitmap, do: write_data(display, line)
    {:ok, display}
  end

  def execute(_display, command), do: {:unsupported, command}

  defp clear(display), do: display |> write_instruction(@cmd_clear_display) |> delay(2)

  defp home(display), do: display |> write_instruction(@cmd_return_home) |> delay(2)

  ##
  ## Low level data pushing commands
  ##

  # Set the DDRAM address corresponding to the specified cursor position.
  defp set_cursor(display, cursor_row, cursor_col) when cursor_row >= 0 and cursor_col >= 0 do
    cursor_position = determine_cursor_position({display.rows, display.cols}, {cursor_row, cursor_col})
    write_instruction(display, @cmd_set_ddram_address ||| cursor_position)
  end

  defp set_backlight(display, flag) when is_boolean(flag) do
    # Set backlight and write 0 (nothing) to trigger it.
    %{display | backlight: flag} |> expander_write(0)
  end

  defp disable_entry_mode_flag(display, flag) do
    entry_mode = display.entry_mode &&& ~~~flag
    %{display | entry_mode: entry_mode} |> write_feature(:entry_mode)
  end

  defp enable_entry_mode_flag(display, flag) do
    entry_mode = display.entry_mode ||| flag
    %{display | entry_mode: entry_mode} |> write_feature(:entry_mode)
  end

  defp disable_display_control_flag(display, flag) do
    display_control = display.display_control &&& ~~~flag
    %{display | display_control: display_control} |> write_feature(:display_control)
  end

  defp enable_display_control_flag(display, flag) do
    display_control = display.display_control ||| flag
    %{display | display_control: display_control} |> write_feature(:display_control)
  end

  # Write a feature based on the display state.
  defp write_feature(display, feature_key) when is_atom(feature_key) do
    display |> write_instruction(Map.fetch!(display, feature_key))
  end

  defp write_instruction(display, byte), do: write_byte(display, byte, 0)
  defp write_data(display, byte), do: write_byte(display, byte, 1)

  defp write_byte(display, byte, mode) when is_integer(byte) and mode in 0..1 do
    <<high_four_bits::4, low_four_bits::4>> = <<byte>>

    display
    |> write_four_bits(high_four_bits, mode)
    |> write_four_bits(low_four_bits, mode)
  end

  defp write_four_bits(display, four_bits, mode \\ 0)
       when is_integer(four_bits) and four_bits in 0..16 and mode in 0..1 do
    byte = four_bits <<< 4 ||| mode
    display |> expander_write(byte) |> pulse_enable(byte)
  end

  defp pulse_enable(display, byte) do
    display
    |> expander_write(byte ||| @enable_bit)
    |> expander_write(byte &&& ~~~@enable_bit)
  end

  defp expander_write(%{i2c_ref: i2c_ref, i2c_address: i2c_address, backlight: backlight} = display, byte)
       when is_reference(i2c_ref) and is_integer(i2c_address) and is_boolean(backlight) and is_integer(byte) do
    data = if(backlight, do: <<byte ||| @backlight_on>>, else: <<byte>>)
    :ok = SerialBus.write(i2c_ref, i2c_address, data)
    display
  end

  defp delay(display, milliseconds) do
    with :ok <- Process.sleep(milliseconds), do: display
  end
end