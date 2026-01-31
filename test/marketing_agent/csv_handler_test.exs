defmodule MarketingAgent.CsvHandlerTest do
  use MarketingAgent.DataCase, async: true

  alias MarketingAgent.CsvHandler
  alias MarketingAgent.Contacts

  describe "import/2" do
    setup do
      # Create a temp CSV file
      csv_content = """
      Company,First Name,Last Name,Email,Title,Segment
      Acme Corp,John,Doe,john@acme.com,CTO,enterprise
      Tech Inc,Jane,Smith,jane@tech.com,VP Engineering,startup
      """

      path = Path.join(System.tmp_dir!(), "test_import_#{:erlang.unique_integer()}.csv")
      File.write!(path, csv_content)

      on_exit(fn -> File.rm(path) end)

      {:ok, path: path}
    end

    test "imports contacts from CSV file", %{path: path} do
      result = CsvHandler.import_contacts(path)

      assert result.success == 2
      assert result.failed == 0
      assert result.total == 2

      # Verify contacts were created
      contacts = Contacts.list_contacts()
      assert length(contacts) == 2

      acme = Contacts.get_contact_by_email("john@acme.com")
      assert acme.company == "Acme Corp"
      assert acme.first_name == "John"
      assert acme.last_name == "Doe"
      assert acme.title == "CTO"
      assert acme.segment == "enterprise"
    end

    test "handles upsert mode", %{path: path} do
      # First import
      CsvHandler.import_contacts(path)

      # Modify CSV with updated data
      updated_csv = """
      Company,First Name,Last Name,Email,Title,Segment
      Acme Corp Updated,John,Doe,john@acme.com,CEO,enterprise
      """

      updated_path = Path.join(System.tmp_dir!(), "test_upsert_#{:erlang.unique_integer()}.csv")
      File.write!(updated_path, updated_csv)

      # Import with upsert
      result = CsvHandler.import_contacts(updated_path, mode: :upsert)

      assert result.updated == 1

      # Verify contact was updated
      acme = Contacts.get_contact_by_email("john@acme.com")
      assert acme.company == "Acme Corp Updated"
      assert acme.title == "CEO"

      File.rm(updated_path)
    end

    test "validates without importing in dry-run mode", %{path: path} do
      result = CsvHandler.import_contacts(path, dry_run: true)

      assert result.success == 2
      assert result.failed == 0

      # Verify no contacts were created
      contacts = Contacts.list_contacts()
      assert length(contacts) == 0
    end

    test "handles missing required fields" do
      csv_content = """
      Email,First Name
      test@example.com,Test
      """

      path = Path.join(System.tmp_dir!(), "test_invalid_#{:erlang.unique_integer()}.csv")
      File.write!(path, csv_content)

      result = CsvHandler.import_contacts(path)

      assert result.failed == 1
      assert length(result.errors) == 1

      File.rm(path)
    end

    test "applies default segment to all imports", %{path: path} do
      CsvHandler.import_contacts(path, segment: "imported-segment")

      contacts = Contacts.list_contacts()
      assert Enum.all?(contacts, fn c -> c.segment == "imported-segment" end)
    end
  end

  describe "export/1" do
    setup do
      # Create some test contacts
      {:ok, contact1} = Contacts.create_contact(%{
        company: "Export Corp",
        first_name: "Alice",
        last_name: "Wonder",
        email: "alice@export.com",
        segment: "export-test"
      })

      {:ok, contact2} = Contacts.create_contact(%{
        company: "Export Inc",
        first_name: "Bob",
        last_name: "Builder",
        email: "bob@export.com",
        segment: "export-test"
      })

      {:ok, contacts: [contact1, contact2]}
    end

    test "exports contacts to CSV format", %{contacts: _contacts} do
      csv = CsvHandler.export()

      assert csv =~ "Company"
      assert csv =~ "Export Corp"
      assert csv =~ "Export Inc"
      assert csv =~ "alice@export.com"
      assert csv =~ "bob@export.com"
    end

    test "filters by segment" do
      # Create contact in different segment
      {:ok, _} = Contacts.create_contact(%{
        company: "Other Corp",
        email: "other@other.com",
        segment: "other-segment"
      })

      csv = CsvHandler.export(segment: "export-test")

      assert csv =~ "Export Corp"
      refute csv =~ "Other Corp"
    end

    test "exports only specified columns" do
      csv = CsvHandler.export(columns: [:company, :email])

      assert csv =~ "Company"
      assert csv =~ "Email"
      refute csv =~ "First Name"
      refute csv =~ "Title"
    end
  end

  describe "sample_template/0" do
    test "returns valid CSV template" do
      template = CsvHandler.sample_template()

      assert template =~ "company"
      assert template =~ "first_name"
      assert template =~ "email"
      assert template =~ "Acme Corp"
    end
  end

  describe "validate/2" do
    test "validates CSV without importing" do
      csv_content = """
      Company,Email
      Valid Corp,valid@valid.com
      """

      path = Path.join(System.tmp_dir!(), "test_validate_#{:erlang.unique_integer()}.csv")
      File.write!(path, csv_content)

      result = CsvHandler.validate(path)

      assert result.success == 1
      assert result.failed == 0

      # Ensure nothing was imported
      assert Contacts.list_contacts() == []

      File.rm(path)
    end
  end
end
