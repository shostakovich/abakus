defmodule AbakusWeb.Kasse.CurrentParticipant do
  @moduledoc "`on_mount` for the Kasse's pages: assigns `current_participant`, the person the signed-in user is."

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     Phoenix.Component.assign(
       socket,
       :current_participant,
       socket.assigns.current_scope.participant
     )}
  end
end
