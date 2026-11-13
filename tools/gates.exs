defmodule Gates do
  @gates [
    {"tests/proof_gate.gd", [:golden], ["--control=flip"]},
    {"tests/hash_proof.gd", [], ["--control=flip"]},
    {"tests/replica_gate.gd", [:mujoco, "--sends=400"], ["--control=altered", "--control=split", "--control=badstate"]},
    {"tests/byz_gate.gd", ["--ticks=1920"],
     ~w(alter split swap decode stale halves size header leak halftag sametick fifo) |> Enum.map(&"--control=#{&1}")},
    {"tests/router_trace.gd", [:trace, "--ticks=210"], ~w(flip flood silent order phase) |> Enum.map(&"--control=#{&1}")}
  ]
  @timeout_ms 600_000

  def main do
    godot = System.get_env("GODOT") || fail("set GODOT to the double-precision editor")
    golden = System.get_env("PACKET_GOLDEN")
    mujoco = System.get_env("MUJOCO_ELF")
    trace = Path.join(System.tmp_dir!(), "router.trace")

    results =
      for {script, base, controls} <- @gates, run <- [nil | controls] do
        if (:golden in base and golden == nil) or (:mujoco in base and mujoco == nil) do
          IO.puts("SKIP #{script}: set PACKET_GOLDEN and MUJOCO_ELF to run it")
          :skip
        else
          args = Enum.map(base, fn :golden -> golden; :mujoco -> mujoco; :trace -> trace; a -> a end) ++ List.wrap(run)
          out = engine(godot, ["--headless", "--path", ".", "-s", script, "--" | args])
          verdict = verdict(out, run)
          IO.puts("#{if verdict == :ok, do: "ok  ", else: "BAD "} #{script} #{Enum.join(args, " ")}: #{last_result(out)}")
          verdict
        end
      end

    bad = Enum.count(results, &(&1 == :bad))
    IO.puts("RESULT: #{if bad == 0, do: "PASS", else: "FAIL #{bad} runs"}")
    System.halt(if bad == 0, do: 0, else: 1)
  end

  defp verdict(out, nil), do: if(out =~ ~r/^RESULT: PASS$/m, do: :ok, else: :bad)

  defp verdict(out, _control) do
    if out =~ ~r/^RESULT: FAIL/m and not (out =~ ~r/^RESULT: (PASS|ERROR)/m), do: :ok, else: :bad
  end

  defp last_result(out) do
    out |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "RESULT:")) |> List.last() || "no RESULT line"
  end

  defp engine(godot, args) do
    port = Port.open({:spawn_executable, godot}, [:binary, :exit_status, :stderr_to_stdout, args: args])
    {:os_pid, pid} = Port.info(port, :os_pid)
    collect(port, pid, "", System.monotonic_time(:millisecond) + @timeout_ms)
  end

  defp collect(port, pid, acc, deadline) do
    left = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} -> collect(port, pid, acc <> data, deadline)
      {^port, {:exit_status, _}} -> acc
    after
      left ->
        System.cmd("kill", ["-9", Integer.to_string(pid)])
        acc <> "\nkilled after the timeout\n"
    end
  end

  defp fail(msg) do
    IO.puts(:stderr, "gates: " <> msg)
    System.halt(2)
  end
end

Gates.main()
