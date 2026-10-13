defmodule Inex.FiltersTest do
  use ExUnit.Case, async: true

  alias Inex.Filters

  doctest Inex.Filters

  describe "to_table_params/1" do
    test "supports integer, string and shortcut variables" do
      assert Filters.to_table_params([{3, 74}, {"sexo", "mujeres"}, {:sex, 1}]) ==
               [tv: "3:74", tv: "sexo:mujeres", tv: "18:1"]
    end

    test "supports tpx tables with Tempus3 ids" do
      assert Filters.to_table_params([{"349~id", "16473~id"}]) == [tv: "349~id:16473~id"]
    end

    test "expands lists of values into repeated params" do
      assert Filters.to_table_params([{70, [9003, 8999]}]) == [tv: "70:9003", tv: "70:8999"]
    end
  end

  describe "to_operation_params/1" do
    test "numbers the filter groups" do
      assert Filters.to_operation_params([{115, 29}, {3, 84}, {762, :all}]) ==
               [g1: "115:29", g2: "3:84", g3: "762:"]
    end

    test "puts the values of a group under the same key" do
      assert Filters.to_operation_params(%{115 => [29, 8]}) == [g1: "115:29", g1: "115:8"]
    end
  end

  describe "validate/1" do
    test "accepts lists and maps" do
      assert {:ok, [{3, 74}]} = Filters.validate([{3, 74}])
      assert {:ok, [{3, 74}]} = Filters.validate(%{3 => 74})
      assert {:ok, [data_type: :all]} = Filters.validate(data_type: :all)
    end

    test "rejects unknown shortcuts" do
      assert {:error, message} = Filters.validate(galaxy: 1)
      assert message =~ "invalid filter {:galaxy, 1}"
    end

    test "rejects invalid variables and values" do
      assert {:error, _message} = Filters.validate([{0, 1}])
      assert {:error, _message} = Filters.validate([{"", 1}])
      assert {:error, _message} = Filters.validate([{3, -1}])
      assert {:error, _message} = Filters.validate([{3, []}])
      assert {:error, _message} = Filters.validate([{3, 1.5}])
      assert {:error, _message} = Filters.validate([:not_a_tuple])
      assert {:error, _message} = Filters.validate("3:74")
    end
  end

  test "shortcuts match the ones of the official R package" do
    assert %{national: 349, province: 115, ccaa: 70, municipality: 19, data_type: 3, sex: 18} =
             Filters.shortcuts()
  end
end
