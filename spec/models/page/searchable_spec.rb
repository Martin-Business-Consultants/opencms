# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page::Searchable do
  def indexed(id) = Page.connection.select_value(Page.send(:sanitize_sql_array, ["SELECT title FROM pages_fts WHERE rowid = ?", id]))

  it "keeps the search index in step with the page" do
    page = Page.create!(slug: "about", title: "About", status: "draft", locale: "en")
    expect(indexed(page.id)).to eq("About")

    page.update!(title: "About us")
    expect(indexed(page.id)).to eq("About us")

    page.destroy_permanently!
    expect(indexed(page.id)).to be_nil
  end
end
