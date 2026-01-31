defmodule MarketingAgent.CsvHandler do
  @moduledoc """
  Comprehensive CSV import/export functionality for contacts.

  Features:
  - Flexible column mapping (auto-detects common column names)
  - Upsert mode (update existing contacts by email)
  - Dry-run mode for validation without importing
  - Progress reporting
  - Export with customizable columns
  - Support for different CSV formats
  """

  alias MarketingAgent.Contacts
  alias MarketingAgent.Contacts.Contact

  @doc """
  Import contacts from a CSV file.

  Options:
    - :mode - :insert (default), :upsert (update existing by email)
    - :dry_run - true/false, validate without importing
    - :segment - default segment for imported contacts
    - :on_progress - callback function for progress updates
    - :skip_invalid - true to skip invalid rows, false to stop on error

  Returns:
    %{
      success: count,
      failed: count,
      updated: count,
      skipped: count,
      errors: [%{row: n, error: msg}]
    }
  """
  def import_contacts(file_path, opts \\ []) do
    mode = Keyword.get(opts, :mode, :insert)
    dry_run = Keyword.get(opts, :dry_run, false)
    default_segment = Keyword.get(opts, :segment)
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)
    skip_invalid = Keyword.get(opts, :skip_invalid, true)

    result = %{
      success: 0,
      failed: 0,
      updated: 0,
      skipped: 0,
      errors: [],
      total: 0
    }

    with {:ok, content} <- File.read(file_path),
         {:ok, {headers, rows}} <- parse_csv(content) do

      total_rows = length(rows)
      column_map = build_column_map(headers)

      result = %{result | total: total_rows}

      rows
      |> Enum.with_index(2)  # Start at 2 (row 1 is headers)
      |> Enum.reduce(result, fn {row, row_num}, acc ->
        # Progress callback
        on_progress.(%{current: row_num - 1, total: total_rows})

        attrs = row_to_attrs(row, column_map, headers)
        attrs = if default_segment, do: Map.put(attrs, :segment, default_segment), else: attrs

        if dry_run do
          validate_row(attrs, row_num, acc, skip_invalid)
        else
          import_row(attrs, row_num, acc, mode, skip_invalid)
        end
      end)
    else
      {:error, :enoent} -> %{result | errors: [%{row: 0, error: "File not found: #{file_path}"}]}
      {:error, reason} -> %{result | errors: [%{row: 0, error: "Parse error: #{inspect(reason)}"}]}
    end
  end

  @doc """
  Export contacts to CSV format.

  Options:
    - :columns - list of columns to include (default: all standard fields)
    - :segment - filter by segment
    - :status - filter by status
    - :include_headers - true/false (default: true)

  Returns: CSV string
  """
  def export(opts \\ []) do
    columns = Keyword.get(opts, :columns, default_export_columns())
    include_headers = Keyword.get(opts, :include_headers, true)

    contacts = Contacts.list_contacts(opts)

    rows = Enum.map(contacts, fn contact ->
      Enum.map(columns, fn col ->
        value = Map.get(contact, col)
        format_value(value)
      end)
    end)

    if include_headers do
      header_row = Enum.map(columns, &column_to_header/1)
      [header_row | rows]
    else
      rows
    end
    |> NimbleCSV.RFC4180.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc """
  Export contacts to a file.
  """
  def export_to_file(file_path, opts \\ []) do
    csv_content = export(opts)
    File.write(file_path, csv_content)
  end

  @doc """
  Validate a CSV file without importing.
  Returns validation results with detailed error messages.
  """
  def validate(file_path, opts \\ []) do
    import_contacts(file_path, Keyword.put(opts, :dry_run, true))
  end

  @doc """
  Get a sample CSV template with headers.
  """
  def sample_template do
    headers = [
      "company",
      "first_name",
      "last_name",
      "email",
      "title",
      "phone",
      "linkedin_url",
      "website",
      "segment",
      "personalization",
      "notes"
    ]

    sample_row = [
      "Acme Corp",
      "John",
      "Doe",
      "john@acmecorp.com",
      "VP Engineering",
      "+1-555-1234",
      "https://linkedin.com/in/johndoe",
      "https://acmecorp.com",
      "enterprise",
      "your innovative RTB platform",
      "Met at conference"
    ]

    [headers, sample_row]
    |> NimbleCSV.RFC4180.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp parse_csv(content) do
    try do
      lines = String.split(content, ~r/\r?\n/, trim: true)

      case lines do
        [] ->
          {:error, "Empty CSV file"}

        [header_line | data_lines] ->
          headers = parse_csv_row(header_line)
          rows = Enum.map(data_lines, &parse_csv_row/1)
          # Filter out empty rows
          rows = Enum.reject(rows, fn row -> Enum.all?(row, &(&1 == "")) end)
          {:ok, {headers, rows}}
      end
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp parse_csv_row(line) do
    # Handle both quoted and unquoted CSV
    line
    |> NimbleCSV.RFC4180.parse_string(skip_headers: false)
    |> List.first([])
  rescue
    # Fallback to simple split for malformed CSV
    _ -> String.split(line, ",") |> Enum.map(&String.trim/1)
  end

  # Build a map of normalized column names to indices
  defp build_column_map(headers) do
    headers
    |> Enum.with_index()
    |> Enum.map(fn {header, idx} ->
      normalized = normalize_header(header)
      {normalized, idx}
    end)
    |> Enum.into(%{})
  end

  # Normalize header names to handle variations
  defp normalize_header(header) do
    header
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[\s_-]+/, "_")
    |> map_header_alias()
  end

  # Map common header variations to standard names
  defp map_header_alias(header) do
    aliases = %{
      # Company variations
      "company" => :company,
      "company_name" => :company,
      "organization" => :company,
      "organisation" => :company,
      "business" => :company,
      "account" => :company,

      # Name variations
      "first_name" => :first_name,
      "firstname" => :first_name,
      "first" => :first_name,
      "given_name" => :first_name,

      "last_name" => :last_name,
      "lastname" => :last_name,
      "last" => :last_name,
      "surname" => :last_name,
      "family_name" => :last_name,

      "full_name" => :full_name,
      "name" => :full_name,
      "contact_name" => :full_name,

      # Email variations
      "email" => :email,
      "email_address" => :email,
      "e_mail" => :email,
      "contact_email" => :email,
      "work_email" => :email,

      # Title variations
      "title" => :title,
      "job_title" => :title,
      "position" => :title,
      "role" => :title,
      "designation" => :title,

      # Phone variations
      "phone" => :phone,
      "phone_number" => :phone,
      "telephone" => :phone,
      "mobile" => :phone,
      "cell" => :phone,
      "contact_number" => :phone,

      # LinkedIn variations
      "linkedin_url" => :linkedin_url,
      "linkedin" => :linkedin_url,
      "linkedin_profile" => :linkedin_url,
      "li_url" => :linkedin_url,

      # Website variations
      "website" => :website,
      "url" => :website,
      "web" => :website,
      "company_website" => :website,
      "homepage" => :website,

      # Segment variations
      "segment" => :segment,
      "list" => :segment,
      "category" => :segment,
      "group" => :segment,
      "tag" => :segment,

      # Other fields
      "personalization" => :personalization,
      "custom" => :personalization,
      "notes" => :notes,
      "comments" => :notes,
      "description" => :notes,

      # Industry/enrichment fields
      "industry" => :industry,
      "company_size" => :company_size,
      "size" => :company_size,
      "employees" => :company_size,
      "location" => :location,
      "city" => :location,
      "country" => :location,

      # Consent
      "consent_source" => :consent_source,
      "source" => :consent_source,
      "lead_source" => :consent_source
    }

    Map.get(aliases, header, String.to_atom(header))
  end

  defp row_to_attrs(row, column_map, _headers) do
    attrs = %{}

    # Extract values based on column mapping
    # column_map is %{:field_atom => index}
    attrs = Enum.reduce(column_map, attrs, fn {field_atom, idx}, acc ->
      value = Enum.at(row, idx, "")

      if field_atom && value != "" do
        Map.put(acc, field_atom, String.trim(value))
      else
        acc
      end
    end)

    # Handle full_name splitting
    attrs = case Map.get(attrs, :full_name) do
      nil -> attrs
      full_name ->
        parts = String.split(full_name, " ", parts: 2)
        attrs
        |> Map.put_new(:first_name, Enum.at(parts, 0))
        |> Map.put_new(:last_name, Enum.at(parts, 1, ""))
        |> Map.delete(:full_name)
    end

    # Default consent source
    Map.put_new(attrs, :consent_source, "csv_import")
  end

  defp validate_row(attrs, row_num, acc, skip_invalid) do
    changeset = Contact.changeset(%Contact{}, attrs)

    if changeset.valid? do
      %{acc | success: acc.success + 1}
    else
      error_msg = format_changeset_errors(changeset)
      error = %{row: row_num, error: error_msg, data: attrs}

      if skip_invalid do
        %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
      else
        %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
      end
    end
  end

  defp import_row(attrs, row_num, acc, mode, skip_invalid) do
    result = case mode do
      :upsert -> upsert_contact(attrs)
      :insert -> Contacts.create_contact(attrs)
    end

    case result do
      {:ok, _contact} ->
        %{acc | success: acc.success + 1}

      {:updated, _contact} ->
        %{acc | updated: acc.updated + 1}

      {:skipped, _reason} ->
        %{acc | skipped: acc.skipped + 1}

      {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
        error_msg = format_changeset_errors(changeset)
        error = %{row: row_num, error: error_msg, data: attrs}

        if skip_invalid do
          %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
        else
          %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
        end

      {:error, reason} ->
        error = %{row: row_num, error: inspect(reason), data: attrs}
        %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
    end
  end

  defp upsert_contact(attrs) do
    email = Map.get(attrs, :email)

    cond do
      is_nil(email) or email == "" ->
        # No email - try to insert
        Contacts.create_contact(attrs)

      existing = Contacts.get_contact_by_email(email) ->
        # Update existing contact
        case Contacts.update_contact(existing, attrs) do
          {:ok, contact} -> {:updated, contact}
          error -> error
        end

      true ->
        # Insert new contact
        Contacts.create_contact(attrs)
    end
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map(fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
    |> Enum.join("; ")
  end

  defp default_export_columns do
    [
      :company,
      :first_name,
      :last_name,
      :email,
      :title,
      :phone,
      :linkedin_url,
      :website,
      :segment,
      :status,
      :industry,
      :company_size,
      :location,
      :personalization,
      :notes,
      :emails_sent,
      :emails_opened,
      :last_contacted_at
    ]
  end

  defp column_to_header(atom) when is_atom(atom) do
    atom
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_value(nil), do: ""
  defp format_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_value(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
  defp format_value(value) when is_list(value), do: Enum.join(value, "; ")
  defp format_value(value) when is_map(value), do: Jason.encode!(value)
  defp format_value(value), do: to_string(value)
end
