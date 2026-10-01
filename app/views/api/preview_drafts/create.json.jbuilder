# frozen_string_literal: true

# Both URLs are the Astro site's /_preview/<path>?preview=<token>, nil when
# Settings › General has no site base URL. `preview_url` used to be the CMS's
# own renderer, which is gone; it stays for older clients.
json.token @issued[:token]
json.expires_at @issued[:expires_at]
json.preview_url Preview.public_url(@page.path, @issued[:token])
json.public_preview_url Preview.public_url(@page.path, @issued[:token])
