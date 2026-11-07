defmodule Abakus.Bookkeeping.Elster do
  @moduledoc """
  ELSTER, the tax offices' gateway, reached through ERiC (ADR 0035) by `client/0`. The vendor id (Hersteller-ID)
  comes from `ELSTER_VENDOR_ID`; with ELSTER's demo vendor id every return carries the test flag, so the tax office
  takes it but does not process it.
  """

  @demo_vendor_id "74931"

  @typedoc """
  A return to send: the owner's tax number with the Landesnummer of its state, which ERiC writes in ELSTER's format
  and `xml` builds the return with, its Datenart version such as `UStVA_2027`, the ELSTER certificate (.pfx) and its
  PIN, as a function so that no crash report shows it.
  """
  @type submission :: %{
          tax_number: String.t(),
          state_number: String.t(),
          xml: (elster_tax_number :: String.t() -> String.t()),
          datenart_version: String.t(),
          certificate: binary,
          pin: (-> String.t())
        }

  @typedoc "What ELSTER gave back for a sent return: its transfer ticket and transmission protocol (a PDF)."
  @type receipt :: %{transfer_ticket: String.t() | nil, protocol: binary | nil}

  @doc "Whether ERiC is there to send with."
  @callback available?() :: boolean

  @doc "Validates and sends the return; the error is ELSTER's or ERiC's message, in German."
  @callback submit(submission) :: {:ok, receipt} | {:error, String.t()}

  def client, do: config()[:client]

  def vendor_id, do: config()[:vendor_id]

  @doc "Whether returns are sent as test cases: with ELSTER's demo vendor id."
  def test?, do: vendor_id() == @demo_vendor_id

  @doc "Whether returns can be sent: a vendor id and ERiC."
  def available?, do: vendor_id() != nil and client().available?()

  defp config, do: Application.fetch_env!(:abakus, __MODULE__)
end
