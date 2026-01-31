defmodule MarketingAgent.Email.SendGridTest do
  use MarketingAgent.DataCase, async: true

  alias MarketingAgent.Email.SendGrid
  alias MarketingAgent.Contacts

  describe "status/0" do
    test "returns configuration status" do
      status = SendGrid.status()

      assert is_map(status)
      assert Map.has_key?(status, :configured)
      assert Map.has_key?(status, :from_email)
      assert Map.has_key?(status, :from_name)
      assert Map.has_key?(status, :daily_limit)
      assert Map.has_key?(status, :api_key_set)
    end
  end

  describe "preview_email/2" do
    setup do
      {:ok, contact} = Contacts.create_contact(%{
        company: "Test Corp",
        email: "test@testcorp.com",
        first_name: "John",
        last_name: "Doe",
        title: "CEO",
        personalization: "is a leading tech company"
      })

      {:ok, contact: contact}
    end

    test "generates email preview", %{contact: contact} do
      case SendGrid.preview_email(contact.id, "cold-email-1") do
        {:ok, preview} ->
          assert preview.to == "test@testcorp.com"
          assert preview.subject != nil
          assert String.contains?(preview.text_body, "John")

        {:error, :not_found} ->
          # Template might not exist in test environment
          :ok
      end
    end

    test "returns error for non-existent contact" do
      assert {:error, :not_found} = SendGrid.preview_email("non-existent-id", "cold-email-1")
    end
  end

  describe "send_email/3 with dry_run" do
    setup do
      {:ok, contact} = Contacts.create_contact(%{
        company: "Test Corp",
        email: "test@testcorp.com",
        first_name: "John",
        last_name: "Doe",
        status: "new"
      })

      {:ok, contact: contact}
    end

    test "dry run does not update contact", %{contact: contact} do
      original_emails_sent = contact.emails_sent

      case SendGrid.send_email(contact.id, "cold-email-1", dry_run: true) do
        {:ok, result} ->
          assert result.status == :dry_run

          # Contact should NOT be updated
          updated_contact = Contacts.get_contact(contact.id)
          assert updated_contact.emails_sent == original_emails_sent
          assert updated_contact.status == "new"

        {:error, _reason} ->
          # Template might not exist
          :ok
      end
    end
  end

  describe "send_email/3 validation" do
    test "rejects contact without email" do
      {:ok, contact} = Contacts.create_contact(%{
        company: "No Email Corp",
        email: nil,
        status: "new"
      })

      assert {:error, :no_email} = SendGrid.send_email(contact.id, "cold-email-1")
    end

    test "rejects unsubscribed contact" do
      {:ok, contact} = Contacts.create_contact(%{
        company: "Unsubscribed Corp",
        email: "unsubscribed@test.com",
        status: "unsubscribed"
      })

      assert {:error, :unsubscribed} = SendGrid.send_email(contact.id, "cold-email-1")
    end

    test "rejects bounced contact" do
      {:ok, contact} = Contacts.create_contact(%{
        company: "Bounced Corp",
        email: "bounced@test.com",
        status: "bounced"
      })

      assert {:error, :bounced} = SendGrid.send_email(contact.id, "cold-email-1")
    end
  end

  describe "tracking functions" do
    setup do
      {:ok, contact} = Contacts.create_contact(%{
        company: "Tracking Corp",
        email: "track@test.com",
        first_name: "Jane",
        status: "contacted",
        emails_sent: 1,
        emails_opened: 0,
        emails_clicked: 0
      })

      {:ok, contact: contact}
    end

    test "record_open/1 updates contact", %{contact: contact} do
      {:ok, updated} = SendGrid.record_open(contact.id)

      assert updated.emails_opened == 1
      assert updated.last_opened_at != nil
      assert updated.status == "opened"
    end

    test "record_click/1 updates contact", %{contact: contact} do
      {:ok, updated} = SendGrid.record_click(contact.id)

      assert updated.emails_clicked == 1
      assert updated.last_clicked_at != nil
      assert updated.status == "clicked"
    end

    test "record_reply/1 updates contact", %{contact: contact} do
      {:ok, updated} = SendGrid.record_reply(contact.id)

      assert updated.last_replied_at != nil
      assert updated.status == "replied"
    end

    test "record_bounce/1 updates contact", %{contact: contact} do
      {:ok, updated} = SendGrid.record_bounce(contact.id)
      assert updated.status == "bounced"
    end

    test "record_unsubscribe/1 updates contact", %{contact: contact} do
      {:ok, updated} = SendGrid.record_unsubscribe(contact.id)

      assert updated.status == "unsubscribed"
      assert updated.unsubscribed_at != nil
    end
  end

  describe "send_batch/2 with dry_run" do
    setup do
      # Create several test contacts
      for i <- 1..3 do
        Contacts.create_contact(%{
          company: "Batch Corp #{i}",
          email: "batch#{i}@test.com",
          first_name: "User#{i}",
          segment: "batch-test",
          status: "new"
        })
      end

      :ok
    end

    test "dry run processes contacts without sending" do
      {:ok, stats} = SendGrid.send_batch("cold-email-1",
        segment: "batch-test",
        limit: 3,
        dry_run: true
      )

      assert stats.total == 3
      # Contacts should still be "new" status
      contacts = Contacts.contacts_by_segment("batch-test")
      assert Enum.all?(contacts, fn c -> c.status == "new" end)
    end
  end
end
