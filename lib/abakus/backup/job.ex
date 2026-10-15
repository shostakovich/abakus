defmodule Abakus.Backup.Job do
  @moduledoc "Writes a backup every night at 03:00 local time."

  alias Abakus.{Backup, DailyJob}

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: ~T[03:00:00], run: &Backup.run/0)
end
