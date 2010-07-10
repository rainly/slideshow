module DirectiveHelper

# css directive:
#
# lets you use:
#   %css
#     -- inline css code here
#   %end
#
# shortcut for:
#   %content_for :css
#     -- inline css code here
#   %end
#  or
#  <% content_for :css do %>
#    -- inline css code here
#  <% end %>

def css( &block )
  content_for( :css, nil, &block )
end
    
  
end # module DirectiveHelper

class Slideshow::Gen
  include DirectiveHelper
end



