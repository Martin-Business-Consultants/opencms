# frozen_string_literal: true

# Per-form, per-kind email templates. Replaces the single set of
# confirmation_* / notify_emails columns directly on `forms` so editors
# can edit the notification (admin) and confirmation (user) emails as
# first-class records, with subject + body + recipients each.
class CreateFormEmails < ActiveRecord::Migration[8.0]
  def up
    create_table :form_emails do |t|
      t.references :form,      null: false, foreign_key: {on_delete: :cascade}
      t.string  :kind,         null: false
      t.boolean :enabled,      null: false, default: true
      t.string  :subject,      null: false, default: ""
      t.text    :body,         null: false, default: ""
      t.string  :from_field
      t.string  :recipients
      t.timestamps

      t.index [:form_id, :kind], unique: true
    end

    say_with_time "Backfilling form_emails from forms columns" do
      now = Time.current.utc.iso8601
      rows = connection.select_all(<<~SQL).to_a
        SELECT id, title,
               notify_emails,
               confirmation_enabled,
               confirmation_subject,
               confirmation_body,
               confirmation_from_field
        FROM forms
      SQL

      rows.each do |row|
        notify       = row["notify_emails"].to_s
        has_admin    = notify.split(/[,\n]/).map(&:strip).reject(&:empty?).any?
        confirm_on   = ActiveModel::Type::Boolean.new.cast(row["confirmation_enabled"])
        notif_subj   = "[#{row["title"]}] New submission #" + "{{submission_id}}"
        notif_body   = <<~MD
          A new submission has arrived for **{{form_title}}**.

          Submitted at {{submitted_at}} from {{ip}}.
        MD

        connection.execute(<<~SQL)
          INSERT INTO form_emails (form_id, kind, enabled, subject, body, recipients, created_at, updated_at)
          VALUES (
            #{connection.quote(row["id"])},
            'notification',
            #{connection.quote(has_admin ? 1 : 0)},
            #{connection.quote(notif_subj)},
            #{connection.quote(notif_body)},
            #{connection.quote(notify)},
            #{connection.quote(now)},
            #{connection.quote(now)}
          )
        SQL

        confirm_subj = row["confirmation_subject"].to_s.presence || "Thanks for your submission"
        confirm_body = row["confirmation_body"].to_s.presence || <<~MD
          Hi {{name}},

          Thanks for reaching out — we'll get back to you within one business day.

          — The team
        MD

        connection.execute(<<~SQL)
          INSERT INTO form_emails (form_id, kind, enabled, subject, body, from_field, created_at, updated_at)
          VALUES (
            #{connection.quote(row["id"])},
            'confirmation',
            #{connection.quote(confirm_on ? 1 : 0)},
            #{connection.quote(confirm_subj)},
            #{connection.quote(confirm_body)},
            #{connection.quote(row["confirmation_from_field"])},
            #{connection.quote(now)},
            #{connection.quote(now)}
          )
        SQL
      end
    end

    remove_column :forms, :confirmation_enabled
    remove_column :forms, :confirmation_subject
    remove_column :forms, :confirmation_body
    remove_column :forms, :confirmation_from_field
    remove_column :forms, :notify_emails
  end

  def down
    add_column :forms, :notify_emails,           :text
    add_column :forms, :confirmation_enabled,    :boolean, null: false, default: false
    add_column :forms, :confirmation_subject,    :string
    add_column :forms, :confirmation_body,       :text
    add_column :forms, :confirmation_from_field, :string
    drop_table :form_emails
  end
end
