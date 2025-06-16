defmodule XbaseTest do
  use ExUnit.Case
  doctest Xbase

  test "greets the world" do
    assert Xbase.hello() == :world
  end
end
