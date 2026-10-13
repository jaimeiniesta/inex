defmodule Inex.ConfigurationTest do
  # Changes the application environment, so it can't run concurrently with other tests
  use Inex.Case, async: false

  setup do
    previous = Application.get_all_env(:inex)

    on_exit(fn ->
      for {key, _value} <- Application.get_all_env(:inex), do: Application.delete_env(:inex, key)
      for {key, value} <- previous, do: Application.put_env(:inex, key, value)
    end)
  end

  test "uses the configured default language" do
    Application.put_env(:inex, :language, :en)
    stub_ine({:fixture, "operacion_ipc"})

    assert {:ok, _operation} = Inex.Operations.get("IPC")
    assert_ine_request("EN/OPERACION/IPC")

    assert {:ok, _operation} = Inex.Operations.get("IPC", language: :es)
    assert_ine_request("ES/OPERACION/IPC")
  end

  test "uses the configured base URL" do
    Application.put_env(:inex, :base_url, "https://example.com/wstempus/js/")

    assert Inex.Client.build_url("SERIE", ["X"], [], :es) ==
             "https://example.com/wstempus/js/ES/SERIE/X"
  end
end
