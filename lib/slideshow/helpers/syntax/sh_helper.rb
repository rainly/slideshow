module Slideshow
 module Syntax
  module ShHelper

  # sh option defaults
  SH_LANG         = 'ruby'
  SH_LINE_NUMBERS = 'true'

def sh_worker( code, opts )
  
  lang         = opts.fetch( :lang, SH_LANG )  
  line_numbers_value = opts.fetch( :line_numbers, headers.get( 'code-line-numbers', SH_LINE_NUMBERS ))
  line_numbers = (line_numbers_value =~ /true|yes|on/i) ? true : false
     
  # note: code gets highlighted at runtime in client (using JavaScript)  
  code_highlighted = CGI::escapeHTML( code )
  
  css_class = 'code'
  css_class_opt = opts.fetch( :class, nil ) #  large, small, tiny, etc.
  css_class << " #{css_class_opt}" if css_class_opt   # e.g. use/allow multiple classes -> code small, code large, etc.
   
  out =  %{<pre class='#{css_class} brush: #{lang} gutter: #{line_numbers ? 'true' : 'false'}'>}
  out << code_highlighted
  out << %{</pre>\n}
    
  return out 
end  

def sv( *args, &blk )   
  # check for optional hash for options
  opts = args.last.kind_of?(Hash) ? args.pop : {}
   
  code = capture_erb(&blk)
  return if code.empty?
    
  code_highlighted = sv_worker( code, opts )
    
  concat_erb( guard_block( code_highlighted ), blk.binding )
  return
end  
    
end   # module ShHelper
end  # module Syntax
end # module Slideshow

class Slideshow::Gen
  include Slideshow::Syntax::ShHelper
end