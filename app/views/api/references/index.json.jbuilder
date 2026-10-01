# frozen_string_literal: true

json.ref_type @ref_type
json.ref_id @ref_id
json.kind params[:kind].presence
json.pagination do
  json.page @page
  json.per @per
  json.total @total
  json.total_pages [(@total.to_f / @per).ceil, 1].max
end
json.owners(@references.map do |ref|
  owner = ref.owner
  case owner
  when Page
    {type: "Page", id: owner.id, slug: owner.slug, title: owner.title, status: owner.status, kind_via: ref.kind, position: ref.position}
  when CollectionEntry
    {type: "CollectionEntry", id: owner.id, slug: owner.slug, title: owner.title, status: owner.status,
     collection_slug: owner.collection.slug, kind_via: ref.kind, position: ref.position}
  when Global
    {type: "Global", id: owner.id, slug: owner.slug, name: owner.name, kind_via: ref.kind, position: ref.position}
  end
end)
