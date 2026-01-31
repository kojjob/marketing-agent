defmodule MarketingAgent.Templates do
  @moduledoc """
  Email template management and rendering.
  """

  @templates_dir Application.compile_env(:marketing_agent, [MarketingAgent.Config, :templates_dir]) ||
                   Path.expand("../priv/templates", __DIR__)

  # ============================================================================
  # Template Loading
  # ============================================================================

  @doc """
  List all available templates.
  """
  def list_templates do
    templates_dir()
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(fn filename ->
      name = String.replace_suffix(filename, ".md", "")
      template = load_template!(name)

      %{
        name: name,
        subject: template.subject,
        description: template.description,
        variables: template.variables
      }
    end)
  end

  @doc """
  Load a template by name.
  """
  def load_template(name) do
    path = Path.join(templates_dir(), "#{name}.md")

    case File.read(path) do
      {:ok, content} -> {:ok, parse_template(name, content)}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def load_template!(name) do
    case load_template(name) do
      {:ok, template} -> template
      {:error, reason} -> raise "Failed to load template #{name}: #{inspect(reason)}"
    end
  end

  # ============================================================================
  # Template Rendering
  # ============================================================================

  @doc """
  Render a template with contact data.

  ## Variables available:
  - {{first_name}} - Contact's first name
  - {{last_name}} - Contact's last name
  - {{full_name}} - Full name
  - {{company}} - Company name
  - {{title}} - Job title
  - {{personalization}} - Custom personalization hook
  - {{industry}} - Company industry
  - {{company_size}} - Company size
  """
  def render(template_name, contact) when is_binary(template_name) do
    case load_template(template_name) do
      {:ok, template} -> render(template, contact)
      {:error, reason} -> {:error, reason}
    end
  end

  def render(%{subject: subject, body: body}, contact) do
    variables = build_variables(contact)

    rendered_subject = replace_variables(subject, variables)
    rendered_body = replace_variables(body, variables) |> markdown_to_html()

    {:ok, %{
      subject: rendered_subject,
      html_body: rendered_body,
      text_body: body |> replace_variables(variables)
    }}
  end

  @doc """
  Preview a template rendering (returns text version).
  """
  def preview(template_name, contact) do
    case load_template(template_name) do
      {:ok, template} ->
        variables = build_variables(contact)
        subject = replace_variables(template.subject, variables)
        body = replace_variables(template.body, variables)
        {:ok, %{subject: subject, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Template Management
  # ============================================================================

  @doc """
  Create or update a template.
  """
  def save_template(name, subject, body, opts \\ []) do
    description = Keyword.get(opts, :description, "")
    variables = extract_variables(subject <> " " <> body)

    content = """
    ---
    subject: #{subject}
    description: #{description}
    variables: #{Enum.join(variables, ", ")}
    ---

    #{body}
    """

    path = Path.join(templates_dir(), "#{name}.md")
    File.write(path, content)
  end

  @doc """
  Delete a template.
  """
  def delete_template(name) do
    path = Path.join(templates_dir(), "#{name}.md")
    File.rm(path)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp templates_dir do
    Application.get_env(:marketing_agent, MarketingAgent.Config)[:templates_dir] || @templates_dir
  end

  defp parse_template(name, content) do
    case String.split(content, "---", parts: 3) do
      ["", frontmatter, body] ->
        metadata = parse_frontmatter(frontmatter)

        %{
          name: name,
          subject: metadata["subject"] || "No subject",
          description: metadata["description"] || "",
          variables: parse_variables(metadata["variables"]),
          body: String.trim(body)
        }

      _ ->
        # No frontmatter, treat entire content as body
        %{
          name: name,
          subject: "No subject",
          description: "",
          variables: extract_variables(content),
          body: String.trim(content)
        }
    end
  end

  defp parse_frontmatter(frontmatter) do
    frontmatter
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(fn line ->
      case String.split(line, ":", parts: 2) do
        [key, value] -> {String.trim(key), String.trim(value)}
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
    |> Enum.into(%{})
  end

  defp parse_variables(nil), do: []

  defp parse_variables(variables_str) do
    variables_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp extract_variables(content) do
    Regex.scan(~r/\{\{(\w+)\}\}/, content)
    |> Enum.map(fn [_, var] -> var end)
    |> Enum.uniq()
  end

  defp build_variables(contact) when is_map(contact) do
    first_name = contact[:first_name] || contact["first_name"] || ""
    last_name = contact[:last_name] || contact["last_name"] || ""

    %{
      "first_name" => first_name,
      "last_name" => last_name,
      "full_name" => String.trim("#{first_name} #{last_name}"),
      "company" => contact[:company] || contact["company"] || "",
      "title" => contact[:title] || contact["title"] || "",
      "personalization" => contact[:personalization] || contact["personalization"] || "",
      "industry" => contact[:industry] || contact["industry"] || "",
      "company_size" => contact[:company_size] || contact["company_size"] || "",
      "email" => contact[:email] || contact["email"] || ""
    }
  end

  defp replace_variables(text, variables) do
    Enum.reduce(variables, text, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", value || "")
    end)
  end

  defp markdown_to_html(markdown) do
    # Simple markdown to HTML conversion
    # For production, consider using a proper markdown library like Earmark
    markdown
    |> String.replace(~r/\*\*(.+?)\*\*/, "<strong>\\1</strong>")
    |> String.replace(~r/\*(.+?)\*/, "<em>\\1</em>")
    |> String.replace(~r/\[(.+?)\]\((.+?)\)/, "<a href=\"\\2\">\\1</a>")
    |> String.replace(~r/^# (.+)$/m, "<h1>\\1</h1>")
    |> String.replace(~r/^## (.+)$/m, "<h2>\\1</h2>")
    |> String.replace(~r/^### (.+)$/m, "<h3>\\1</h3>")
    |> String.replace(~r/^- (.+)$/m, "<li>\\1</li>")
    |> String.replace(~r/(<li>.+<\/li>\n?)+/, "<ul>\\0</ul>")
    |> String.split("\n\n")
    |> Enum.map(fn para ->
      if String.starts_with?(para, "<") do
        para
      else
        "<p>#{para}</p>"
      end
    end)
    |> Enum.join("\n")
  end
end
