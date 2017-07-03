defmodule TapperContextualTest do

  use ExUnit.Case

  describe "contextual ids" do

    test "put/get in context" do
      Tapper.Ctx.delete_context()

      id = Tapper.Id.test_id()

      ^id = Tapper.Ctx.put_context(id)

      assert ^id = Tapper.Ctx.context()
    end

    test "put overrides existing value" do
      Tapper.Ctx.delete_context()

      id1 = Tapper.Id.test_id()

      ^id1 = Tapper.Ctx.put_context(id1)

      id2 = Tapper.Id.test_id()

      ^id2 = Tapper.Ctx.put_context(id2)

      assert ^id2 = Tapper.Ctx.context()
    end

    test "get in context when no id returns :ignore by default" do
      Application.delete_env(:tapper, :debug_context)

      Tapper.Ctx.delete_context()

      assert :ignore = Tapper.Ctx.context()
    end

    test "get in context when no id with debug :warn returns :ignore" do
      Application.put_env(:tapper, :debug_context, :warn)

      Tapper.Ctx.delete_context()

      Logger.disable(self()) # suppress log output

      assert :ignore = Tapper.Ctx.context()
    end

    test "get in context when no id with debug true raises" do
      Application.put_env(:tapper, :debug_context, true)

      Tapper.Ctx.delete_context()

      assert_raise RuntimeError, fn -> Tapper.Ctx.context() end
    end

    test "get in context when no id with debug truthy raises" do
      Application.put_env(:tapper, :debug_context, :anything)
      Tapper.Ctx.delete_context()

      assert_raise RuntimeError, fn -> Tapper.Ctx.context() end
    end

  end

  describe "contextual api" do
    alias Tapper.Ctx, as: Tapper

    test "start and finish set context" do
      refute Tapper.context?()
      id = Tapper.start(debug: true)
      assert Tapper.context?()
      assert Tapper.context() == id
      :ok = Tapper.finish()
      refute Tapper.context?()
    end

    test "start_span and finish_span set context" do
      refute Tapper.context?()

      prime_id = Tapper.start(debug: true)
      assert Tapper.context?()

      span_id = Tapper.start_span(name: "foo")
      assert Tapper.context?()
      assert Tapper.context() == span_id
      refute span_id == prime_id

      update_id = Tapper.update_span(Tapper.wire_send())
      assert Tapper.context?()
      assert Tapper.context() == update_id
      assert update_id == span_id

      finish_id = Tapper.finish_span(name: "foo")
      assert Tapper.context?()
      assert Tapper.context() == finish_id
      assert finish_id == prime_id

      :ok = Tapper.finish()
      refute Tapper.context?()
    end
  end

end