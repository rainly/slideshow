# builtin text filters
# called before text_to_html
#
# use web filters for processing html/hypertext

module TextFilter

def directives_bang_style_to_percent_style( content )

  # for compatibility allow !SLIDE/!STYLE as an alternative to %slide/%style-directive
  
  bang_count = 0
  
  content.gsub!(/^!(SLIDE|STYLE)/) do |match|
    bang_count += 1
    "%#{$1.downcase}"
  end

  puts "  Patching !-directives (#{bang_count} slide/style-directives)..."

  content
end

def directives_percent_style( content )

  directive_single    = 0
  directive_block_beg = 0
  directive_block_end = 0

  # 1) process known single line directives (e.g. slide, style)

  content.gsub!(/^%([a-zA-Z][a-zA-Z0-9_]*)(.*)/) do |match| 
    directive = $1.downcase
    params    = $2
    if [ 'slide', 'style' ].include?( directive )  
      directive_single += 1
      "<!-- _S9#{directive.upcase}_ #{params} -->"         
    else
      "%#{directive} #{params ? params : ''}"  # skip block or unknown directives
    end
  end


  # 2) process block directives (plus skip %begin/%end comment-blocks)

  inside_block  = false
  inside_helper = false
  
  content2 = ""
  
  content.each_line do |line|
    if line =~ /^%([a-zA-Z][a-zA-Z0-9_]*)(.*)/
      directive = $1.downcase
      params    = $2

      logger.debug "processing %-directive: #{directive}"

      if inside_helper && directive == 'end'
        inside_helper = false
        directive_block_end += 1
        content2 << "%>"        
      elsif inside_block && directive == 'end'
        inside_block = false
        directive_block_end += 1
        content2 << "<% end %>"
      elsif [ 'comment', 'comments', 'begin', 'end' ].include?( directive )  # skip begin/end comment blocks
        content2 << line
      elsif [ 'helper', 'helpers' ].include?( directive )
        inside_helper = true
        directive_block_beg += 1
        content2 << "<%"
      else
        inside_block = true
        directive_block_beg += 1
        content2 << "<% #{directive} #{params ? params:''} do %>"
      end
    else
      content2 << line
    end
  end  
    
  puts "  Preparing %-directives (#{directive_single} slide/style-directives, #{directive_block_beg}/#{directive_block_end} block-directives)..."

  content2
end



def comments_percent_style( content )    
    
    # remove comments
    # % comments
    # %begin multiline comment
    # %end multiline comment

    # track statistics
    comments_multi  = 0
    comments_single = 0
    comments_end    = 0

    # remove multi-line comments
    content.gsub!(/^%(begin|comment|comments).*?%end/m) do |match|
      comments_multi += 1
      ""
    end
    
     # remove everyting starting w/ %end (note, can only be once in file) 
    content.sub!(/^%end.*/m) do |match|
      comments_end += 1
      ""
    end

    # hack/note: 
    #  note multi-line erb expressions/stmts might cause trouble
    #  
    #  %> gets escaped as special case (not treated as comment)
    # <%
    #   whatever
    # %> <!-- trouble here; would get removed as comment!
    #  todo: issue warning?
    
    # remove single-line comments    
    content.gsub!(/(^%$)|(^%[^>].*)/ ) do |match|
      comments_single += 1
      ""
    end
    
    puts "  Removing %-comments (#{comments_single} lines, " +
       "#{comments_multi} begin/end-blocks, #{comments_end} end-blocks)..."
    
    content    
  end

  def skip_end_directive( content )
    # codex-style __SKIP__, __END__ directive
    # ruby note: .*? is non-greedy (shortest-possible) regex match
    content.gsub!(/__SKIP__.*?__END__/m, '')
    content.sub!(/__END__.*/m, '')
    content
  end
  
  def include_helper_hack( content )
    # note: include is a ruby keyword; rename to __include__ so we can use it 
    
    include_counter = 0
    
    content.gsub!( /<%=[ \t]*include/ ) do |match|
      include_counter += 1
      '<%= __include__' 
    end

    puts "  Patching embedded Ruby (erb) code aliases (#{include_counter} include)..."

    content
  end
  
  # allow plugins/helpers; process source (including header) using erb    
  def erb( content )
    puts "  Running embedded Ruby (erb) code/helpers..."
    
    content =  ERB.new( content ).result( binding() )
    content
  end

  def erb_django_style( content )

    # replace expressions (support for single lines only)
    #  {{ expr }}  ->  <%= expr %>
    #  {% stmt %}  ->  <%  stmt %>   !! add in do if missing (for convenience)

    erb_expr = 0
    erb_stmt_beg = 0
    erb_stmt_end = 0

    content.gsub!( /\{\{([^{}\n]+?)\}\}/ ) do |match|
      erb_expr += 1
      "<%= #{$1} %>"
    end

    content.gsub!( /\{%[ \t]*end[ \t]*%\}/ ) do |match|
      erb_stmt_end += 1
      "<% end %>"
    end

    content.gsub!( /\{%([^%\n]+?)%\}/ ) do |match|
      erb_stmt_beg += 1
      if $1.include?('do') 
        "<% #{$1} %>"
      else
        "<% #{$1} do %>"
      end
    end

    puts "  Patching embedded Ruby (erb) code Django-style (#{erb_expr} {{-expressions," +
       " #{erb_stmt_beg}/#{erb_stmt_end} {%-statements)..."
         
    content        
  end

  def code_block_curly_style( content )
    # replace {{{  w/ <pre class='code'>
    # replace }}}  w/ </pre>
    
    # track statistics
    code_begin = 0
    code_end   = 0    
    
    content.gsub!( "{{{{{{", "<pre class='code'>_S9BEGIN_" )
    content.gsub!( "}}}}}}", "_S9END_</pre>" )  
    
    content.gsub!( "{{{" ) do |match|
      code_begin += 1
      "<pre class='code'>"
    end    
    
    content.gsub!( "}}}" ) do |match|
      code_end += 1
      "</pre>"
    end
    
    # restore escaped {{{}}} 
    content.gsub!( "_S9BEGIN_", "{{{" )
    content.gsub!( "_S9END_", "}}}" )
    
    puts "  Patching code blocks (#{code_begin}/#{code_end} {{{/}}}-lines)..."    
    
    content
  end

end # module TextFilter

class Slideshow::Gen
  include TextFilter
end