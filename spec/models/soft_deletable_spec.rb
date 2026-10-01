# frozen_string_literal: true

require "rails_helper"

RSpec.describe SoftDeletable do
  def make_page(attrs = {})
    Page.create!({
      slug:        "p-#{SecureRandom.hex(3)}",
      title:       "T",
      status:      "draft",
      locale:      "en",
      blocks:      [],
      schema:      {"fields" => []},
      frontmatter: {},
      seo:         {}
    }.merge(attrs))
  end

  describe "scopes" do
    it "default_scope hides discarded rows" do
      kept = make_page
      gone = make_page
      gone.discard!

      expect(Page.pluck(:id)).to contain_exactly(kept.id)
      expect(Page.discarded.pluck(:id)).to contain_exactly(gone.id)
      expect(Page.with_discarded.pluck(:id)).to contain_exactly(kept.id, gone.id)
    end
  end

  describe "#discard! / #restore!" do
    it "stamps and clears deleted_at" do
      page = make_page
      expect { page.discard! }.to change { page.reload.deleted_at }.from(nil)
      expect(page.discarded?).to eq(true)

      expect { page.restore! }.to change { page.reload.deleted_at }.to(nil)
      expect(page.kept?).to eq(true)
    end

    it "trashes and restores a record whose stored content no longer validates" do
      page = make_page
      # Simulate legacy data written before validation tightened.
      page.update_column(:title, "")
      expect(page.reload).not_to be_valid

      expect { page.discard! }.to change { page.reload.deleted_at }.from(nil)
      expect { page.restore! }.to change { page.reload.deleted_at }.to(nil)
      expect(page.reload.title).to eq("")
    end

    it "is idempotent" do
      page = make_page
      page.discard!
      stamp = page.reload.deleted_at
      page.discard!
      expect(page.reload.deleted_at).to eq(stamp)
    end
  end

  describe "Page#discard! cascade" do
    it "soft-deletes direct children" do
      parent = make_page(slug: "parent")
      child  = make_page(slug: "child", parent_id: parent.id)

      parent.discard!

      expect(parent.reload.discarded?).to eq(true)
      expect(Page.with_discarded.find(child.id).discarded?).to eq(true)
    end
  end

  describe "destroy_permanently!" do
    it "actually destroys the row" do
      page = make_page
      page.discard!

      expect { page.destroy_permanently! }
        .to change { Page.with_discarded.where(id: page.id).count }.from(1).to(0)
    end
  end
end
