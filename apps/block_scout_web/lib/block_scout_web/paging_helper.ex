defmodule BlockScoutWeb.PagingHelper do
  @moduledoc """
    Helper for fetching filters and other url query parameters
  """
  import Explorer.Chain, only: [string_to_transaction_hash: 1]
  alias Explorer.Chain.Stability.Validator, as: ValidatorStability
  alias Explorer.Chain.Transaction
  alias Explorer.{Helper, PagingOptions, SortingHelper}

  @page_size 50
  @default_paging_options %PagingOptions{page_size: @page_size + 1}
  @allowed_filter_labels ["validated", "pending"]

  case Application.compile_env(:explorer, :chain_type) do
    :ethereum ->
      @allowed_type_labels [
        "coin_transfer",
        "contract_call",
        "contract_creation",
        "token_transfer",
        "token_creation",
        "blob_transaction"
      ]

    _ ->
      @allowed_type_labels [
        "coin_transfer",
        "contract_call",
        "contract_creation",
        "token_transfer",
        "token_creation"
      ]
  end

  @allowed_token_transfer_type_labels ["ERC-20", "ERC-721", "ERC-1155", "ERC-404"]
  @allowed_nft_type_labels ["ERC-721", "ERC-1155", "ERC-404"]
  @allowed_chain_id [1, 56, 99]
  @allowed_stability_validators_states ["active", "probation", "inactive"]

  def allowed_stability_validators_states, do: @allowed_stability_validators_states

  def paging_options(%{"block_number" => block_number_string, "index" => index_string}, [:validated | _]) do
    with {block_number, ""} <- Integer.parse(block_number_string),
         {index, ""} <- Integer.parse(index_string) do
      [paging_options: %{@default_paging_options | key: {block_number, index}}]
    else
      _ ->
        [paging_options: @default_paging_options]
    end
  end

  def paging_options(%{"inserted_at" => inserted_at_string, "hash" => hash_string}, [:pending | _]) do
    with {:ok, inserted_at, _} <- DateTime.from_iso8601(inserted_at_string),
         {:ok, hash} <- string_to_transaction_hash(hash_string) do
      [paging_options: %{@default_paging_options | key: {inserted_at, hash}, is_pending_tx: true}]
    else
      _ ->
        [paging_options: @default_paging_options]
    end
  end

  def paging_options(_params, _filter), do: [paging_options: @default_paging_options]

  @spec stability_validators_state_options(map()) :: [{:state, list()}, ...]
  def stability_validators_state_options(%{"state_filter" => state}) do
    [state: filters_to_list(state, @allowed_stability_validators_states, :downcase)]
  end

  def stability_validators_state_options(_), do: [state: []]

  @spec token_transfers_types_options(map()) :: [{:token_type, list}]
  def token_transfers_types_options(%{"type" => filters}) do
    [
      token_type: filters_to_list(filters, @allowed_token_transfer_type_labels)
    ]
  end

  def token_transfers_types_options(_), do: [token_type: []]

  @doc """
    Parse 'type' query parameter from request option map
  """
  @spec nft_types_options(map()) :: [{:token_type, list}]
  def nft_types_options(%{"type" => filters}) do
    [
      token_type: filters_to_list(filters, @allowed_nft_type_labels)
    ]
  end

  def nft_types_options(_), do: [token_type: []]

  defp filters_to_list(filters, allowed, variant \\ :upcase)
  defp filters_to_list(filters, allowed, :downcase), do: filters |> String.downcase() |> parse_filter(allowed)
  defp filters_to_list(filters, allowed, :upcase), do: filters |> String.upcase() |> parse_filter(allowed)

  # sobelow_skip ["DOS.StringToAtom"]
  def filter_options(%{"filter" => filter}, fallback) do
    filter = filter |> parse_filter(@allowed_filter_labels) |> Enum.map(&String.to_atom/1)
    if(filter == [], do: [fallback], else: filter)
  end

  def filter_options(_params, fallback), do: [fallback]

  def chain_ids_filter_options(%{"chain_ids" => chain_id}) do
    [
      chain_ids:
        chain_id
        |> String.split(",")
        |> Enum.uniq()
        |> Enum.map(&Helper.parse_integer/1)
        |> Enum.filter(&Enum.member?(@allowed_chain_id, &1))
    ]
  end

  def chain_ids_filter_options(_), do: [chain_id: []]

  # sobelow_skip ["DOS.StringToAtom"]
  def type_filter_options(%{"type" => type}) do
    [type: type |> parse_filter(@allowed_type_labels) |> Enum.map(&String.to_atom/1)]
  end

  def type_filter_options(_params), do: [type: []]

  def method_filter_options(%{"method" => method}) do
    [method: parse_method_filter(method)]
  end

  def method_filter_options(_params), do: [method: []]

  def parse_filter("[" <> filter, allowed_labels) do
    filter
    |> String.trim_trailing("]")
    |> parse_filter(allowed_labels)
  end

  def parse_filter(filter, allowed_labels) when is_binary(filter) do
    filter
    |> String.split(",")
    |> Enum.filter(fn label -> Enum.member?(allowed_labels, label) end)
    |> Enum.uniq()
  end

  def parse_method_filter("[" <> filter) do
    filter
    |> String.trim_trailing("]")
    |> parse_method_filter()
  end

  def parse_method_filter(filter) do
    filter
    |> String.split(",")
    |> Enum.uniq()
  end

  def select_block_type(%{"type" => type}) do
    case String.downcase(type) do
      "uncle" ->
        [
          necessity_by_association: %{
            :transactions => :optional,
            [miner: :names] => :optional,
            :nephews => :required,
            :rewards => :optional
          },
          block_type: "Uncle"
        ]

      "reorg" ->
        [
          necessity_by_association: %{
            :transactions => :optional,
            [miner: :names] => :optional,
            :rewards => :optional
          },
          block_type: "Reorg"
        ]

      _ ->
        select_block_type(nil)
    end
  end

  def select_block_type(_),
    do: [
      necessity_by_association: %{
        :transactions => :optional,
        [miner: :names] => :optional,
        :rewards => :optional
      },
      block_type: "Block"
    ]

  def delete_parameters_from_next_page_params(params) when is_map(params) do
    params
    |> Map.drop([
      "block_hash_or_number",
      "transaction_hash_param",
      "address_hash_param",
      "type",
      "method",
      "filter",
      "q",
      "sort",
      "order",
      "state_filter"
    ])
  end

  def delete_parameters_from_next_page_params(_), do: nil

  def current_filter(%{"filter" => "solidity"}) do
    [filter: :solidity]
  end

  def current_filter(%{"filter" => "vyper"}) do
    [filter: :vyper]
  end

  def current_filter(%{"filter" => "yul"}) do
    [filter: :yul]
  end

  def current_filter(_), do: []

  def search_query(%{"search" => ""}), do: []

  def search_query(%{"search" => search_string}) do
    [search: search_string]
  end

  def search_query(%{"q" => ""}), do: []

  def search_query(%{"q" => search_string}) do
    [search: search_string]
  end

  def search_query(_), do: []

  @spec tokens_sorting(%{required(String.t()) => String.t()}) :: [{:sorting, SortingHelper.sorting_params()}]
  def tokens_sorting(%{"sort" => sort_field, "order" => order}) do
    [sorting: do_tokens_sorting(sort_field, order)]
  end

  def tokens_sorting(_), do: []

  defp do_tokens_sorting("fiat_value", "asc"), do: [asc_nulls_first: :fiat_value]
  defp do_tokens_sorting("fiat_value", "desc"), do: [desc_nulls_last: :fiat_value]
  defp do_tokens_sorting("holder_count", "asc"), do: [asc_nulls_first: :holder_count]
  defp do_tokens_sorting("holder_count", "desc"), do: [desc_nulls_last: :holder_count]
  defp do_tokens_sorting("circulating_market_cap", "asc"), do: [asc_nulls_first: :circulating_market_cap]
  defp do_tokens_sorting("circulating_market_cap", "desc"), do: [desc_nulls_last: :circulating_market_cap]
  defp do_tokens_sorting(_, _), do: []

  @spec smart_contracts_sorting(%{required(String.t()) => String.t()}) :: [{:sorting, SortingHelper.sorting_params()}]
  def smart_contracts_sorting(%{"sort" => sort_field, "order" => order}) do
    [sorting: do_smart_contracts_sorting(sort_field, order)]
  end

  def smart_contracts_sorting(_), do: []

  defp do_smart_contracts_sorting("balance", "asc"), do: [{:asc_nulls_first, :fetched_coin_balance, :address}]
  defp do_smart_contracts_sorting("balance", "desc"), do: [{:desc_nulls_last, :fetched_coin_balance, :address}]
  defp do_smart_contracts_sorting("txs_count", "asc"), do: [{:asc_nulls_first, :transactions_count, :address}]
  defp do_smart_contracts_sorting("txs_count", "desc"), do: [{:desc_nulls_last, :transactions_count, :address}]
  defp do_smart_contracts_sorting(_, _), do: []

  @spec address_transactions_sorting(%{required(String.t()) => String.t()}) :: [
          {:sorting, SortingHelper.sorting_params()}
        ]
  def address_transactions_sorting(%{"sort" => sort_field, "order" => order}) do
    [sorting: do_address_transaction_sorting(sort_field, order)]
  end

  def address_transactions_sorting(_), do: []

  defp do_address_transaction_sorting("value", "asc"), do: [asc: :value]
  defp do_address_transaction_sorting("value", "desc"), do: [desc: :value]
  defp do_address_transaction_sorting("fee", "asc"), do: [{:dynamic, :fee, :asc_nulls_first, Transaction.dynamic_fee()}]

  defp do_address_transaction_sorting("fee", "desc"),
    do: [{:dynamic, :fee, :desc_nulls_last, Transaction.dynamic_fee()}]

  defp do_address_transaction_sorting(_, _), do: []

  @spec validators_stability_sorting(%{required(String.t()) => String.t()}) :: [
          {:sorting, SortingHelper.sorting_params()}
        ]
  def validators_stability_sorting(%{"sort" => sort_field, "order" => order}) do
    [sorting: do_validators_stability_sorting(sort_field, order)]
  end

  def validators_stability_sorting(_), do: []

  defp do_validators_stability_sorting("state", "asc"), do: [asc_nulls_first: :state]
  defp do_validators_stability_sorting("state", "desc"), do: [desc_nulls_last: :state]
  defp do_validators_stability_sorting("address_hash", "asc"), do: [asc_nulls_first: :address_hash]
  defp do_validators_stability_sorting("address_hash", "desc"), do: [desc_nulls_last: :address_hash]

  defp do_validators_stability_sorting("blocks_validated", "asc"),
    do: [{:dynamic, :blocks_validated, :asc_nulls_first, ValidatorStability.dynamic_validated_blocks()}]

  defp do_validators_stability_sorting("blocks_validated", "desc"),
    do: [{:dynamic, :blocks_validated, :desc_nulls_last, ValidatorStability.dynamic_validated_blocks()}]

  defp do_validators_stability_sorting(_, _), do: []

  @spec mud_records_sorting(%{required(String.t()) => String.t()}) :: [
          {:sorting, SortingHelper.sorting_params()}
        ]
  def mud_records_sorting(%{"sort" => sort_field, "order" => order}) do
    [sorting: do_mud_records_sorting(sort_field, order)]
  end

  def mud_records_sorting(_), do: []

  defp do_mud_records_sorting("key_bytes", "asc"), do: [asc_nulls_first: :key_bytes]
  defp do_mud_records_sorting("key_bytes", "desc"), do: [desc_nulls_last: :key_bytes]
  defp do_mud_records_sorting("key0", "asc"), do: [asc_nulls_first: :key0]
  defp do_mud_records_sorting("key0", "desc"), do: [desc_nulls_last: :key0]
  defp do_mud_records_sorting("key1", "asc"), do: [asc_nulls_first: :key1]
  defp do_mud_records_sorting("key1", "desc"), do: [desc_nulls_last: :key1]
  defp do_mud_records_sorting(_, _), do: []
end
