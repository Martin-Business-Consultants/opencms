# frozen_string_literal: true

# Jbuilder views encode the way `render json:` does. Rails' JSON renderer
# passes `escape: false` (action_controller.escape_json_responses is off), so
# "&", "<" and ">" come out as themselves; Jbuilder's own `to_json` would
# write them as &, < and >. The API's responses moved from
# `render json:` to Jbuilder byte-identical, and this keeps them that way for
# text containing those characters (a page titled "Q&A").
ActiveSupport.on_load(:action_view) do
  JbuilderTemplate.prepend(Module.new do
    def target!
      @cached_root || ActiveSupport::JSON.encode(@attributes, escape: false)
    end
  end)
end
