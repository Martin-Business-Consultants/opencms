# frozen_string_literal: true

# Whether the template just received is the one the CMS sends: "current"
# (built from the email's blocks as they are) or "stale".
json.status @email.site_template_status
json.content_digest @email.content_digest
