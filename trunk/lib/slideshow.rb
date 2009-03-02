$KCODE = 'utf'

require 'optparse'
require 'erb'
require 'redcloth'
require 'logger'
require 'fileutils'
require 'ftools'
require 'pp'


module Slideshow

  VERSION = '0.7.7'

# todo: split (command line) options and headers?
# e.g. share (command line) options between slide shows (but not headers?)

class Opts
  
  def initialize
    @hash = {}
  end
    
  def put( key, value )
    key = normalize_key( key )
    setter = "#{key}=".to_sym

    if respond_to? setter
      send setter, value
    else
      @hash[ key ] = value
    end
  end
  
  def gradient=( value )
    put_gradient( value, :theme, :color1, :color2 )
  end
  
  def gradient_colors=( value )
    put_gradient( value, :color1, :color2 )
  end

  def gradient_color=( value )
    put_gradient( value, :color1 )
  end
  
  def gradient_theme=( value )
    put_gradient( value, :theme )
  end
  
  def []( key )
    value = @hash[ normalize_key( key ) ]
    if value.nil?
      puts "** Warning: header '#{key}' undefined"
      "- #{key} not found -"
    else
      value 
    end
  end

  def generate?
    get_boolean( 'generate', false )
  end
  
  def has_includes?
    @hash[ :include ]
  end
  
  def includes
    # fix: use os-agnostic delimiter (use : for Mac/Unix?)
    has_includes? ? @hash[ :include ].split( ';' ) : []
  end
  
  def s5?  
    get_boolean( 's5', false )
  end
  
  def fullerscreen?
    get_boolean( 'fuller', false ) || get_boolean( 'fullerscreen', false )
  end
  
  def manifest  
    get( 'manifest', 's6.txt' )
  end
  
  def output_path
    get( 'output', '.' )
  end

  def code_engine
    get( 'code-engine', DEFAULTS[ :code_engine ] )
  end
  
  def code_txmt
    get( 'code-txmt', DEFAULTS[ :code_txmt ])
  end


  DEFAULTS =
  {
    :title             => 'Untitled Slide Show',
    :footer            => '',
    :subfooter         => '',
    :gradient_theme    => 'dark',
    :gradient_color1   => 'red',
    :gradient_color2   => 'black',

    :code_engine       => 'uv',  # ultraviolet (uv) | coderay (cr)
    :code_txmt         => 'false', # Text Mate Hyperlink for Source?
  }

  def set_defaults      
    DEFAULTS.each_pair do | key, value |
      @hash[ key ] = value if @hash[ key ].nil?
    end
  end

  def get( key, default )
    @hash.fetch( normalize_key(key), default )
  end

private

  def normalize_key( key )
    key.to_s.downcase.tr('-', '_').to_sym
  end
  
  # Assigns the given gradient-* keys to the values in the given string.
  def put_gradient( string, *keys )
    values = string.split( ' ' )

    values.zip(keys).each do |v, k|
      @hash[ normalize_key( "gradient-#{k}" ) ] = v.tr( '-', '_' )
    end
  end
  
  def get_boolean( key, default )
    value = @hash[ normalize_key( key ) ]
    if value.nil?
      default
    else
      (value == true || value =~ /true|yes|on/i) ? true : false
    end
  end

end # class Opts


class Gen

  KNOWN_TEXTILE_EXTNAMES  = [ '.textile', '.t' ]
  KNOWN_MARKDOWN_EXTNAMES = [ '.markdown', '.m', '.mark', '.mkdn', '.md', '.txt', '.text' ]
  KNOWN_EXTNAMES = KNOWN_TEXTILE_EXTNAMES + KNOWN_MARKDOWN_EXTNAMES

  # note: only bluecloth is listed as a dependency in gem specs (because it's Ruby only and, thus, easy to install)
  #  if you want to use other markdown libs install the required/desired lib e.g.
  #  use  gem install rdiscount for rdiscount and so on
  #
  # also note for now the first present markdown library gets used
  #  the search order is first come, first serve, that is: rdiscount, rpeg-markdown, maruku, bluecloth (fallback, always present)
  KNOWN_MARKDOWN_LIBS = [
    [ 'rdiscount',      lambda { |content| RDiscount.new( content ).to_html } ],
    [ 'rpeg-markdown',  lambda { |content| PEGMarkdown.new( content ).to_html } ],
    [ 'maruku',         lambda { |content| Maruku.new( content, {:on_error => :raise} ).to_html }  ],
    [ 'bluecloth',      lambda { |content| BlueCloth.new( content ).to_html } ]
  ] 
  
  BUILTIN_MANIFESTS       = [ 'fullerscreen.txt', 'fullerscreen.txt.gen',
                              's5.txt', 's5.txt.gen',
                              's6.txt', 's6.txt.gen',
                              's5blank.txt.gen' ]
  
  def initialize
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO
    @opts = Opts.new
  end

  # replace w/ attr_reader :logger, :opts ??

  def logger 
    @logger
  end
  
  def opts
    @opts
  end
  
  def headers
    # give access to helpers to opts with a different name
    @opts
  end
  
  def session
    # give helpers/plugins a session-like hash
    @session
  end
  
  def markup_type
    @markup_type   # :textile, :markdown
  end
  
  def load_markdown_libs
    # check for available markdown libs/gems
    # try to require each lib and remove any not installed
    @markdown_libs = []

    KNOWN_MARKDOWN_LIBS.each do |lib|
      begin
        require lib[0]
        @markdown_libs << lib
      rescue LoadError => ex
        logger.debug "Markdown library #{lib[0]} not found. Use gem install #{lib[0]} to install."
      end
    end

    logger.debug "Installed Markdown libraries: #{@markdown_libs.map{ |lib| lib[0] }.join(', ')}"
    logger.debug "Using Markdown library #{@markdown_libs.first[0]}."
  end
  
  # todo: move to filter (for easier reuse)
  def markdown_to_html( content )
    @markdown_libs.first[1].call( content )
  end

  # todo: move to filter (for easier reuse)  
  def textile_to_html( content )
    # turn off hard line breaks
    # turn off span caps (see http://rubybook.ca/2008/08/16/redcloth)
    red = RedCloth.new( content, [:no_span_caps] )
    red.hard_breaks = false
    content = red.to_html
  end
  
  def wrap_markup( text )    
    if markup_type == :textile
      # saveguard with notextile wrapper etc./no further processing needed
      "<notextile>\n#{text}\n</notextile>"
    else
      text
    end
  end
    
  def cache_dir
    PLATFORM =~ /win32/ ? win32_cache_dir : File.join(File.expand_path("~"), ".slideshow")
  end

  def win32_cache_dir
    unless File.exists?(home = ENV['HOMEDRIVE'] + ENV['HOMEPATH'])
      puts "No HOMEDRIVE or HOMEPATH environment variable.  Set one to save a" +
           "local cache of stylesheets for syntax highlighting and more."
      return false
    else
      return File.join(home, 'slideshow')
    end
  end

  def load_manifest( path )
    
    # check if file exists (if yes use custom template package!) - allows you to override builtin package with same name
    if BUILTIN_MANIFESTS.include?( path ) && !File.exists?( path )  
      templatesdir = "#{File.dirname(__FILE__)}/templates"
      logger.debug "use builtin template package"
      logger.debug "templatesdir=#{templatesdir}"
      filename = "#{templatesdir}/#{path}"
    else
      templatesdir = File.dirname( path )
      logger.debug "use custom template package"
      logger.debug "templatesdir=#{templatesdir}"
      filename = path
    end
  
    manifest = []
    puts "  Loading template manifest #{filename}..." 
  
    File.open( filename ).readlines.each_with_index do |line,i|
      case line
      when /^\s*$/
        # skip empty lines
      when /^\s*#.*$/
        # skip comment lines
      else
        logger.debug "line #{i+1}: #{line.strip}"
        values = line.strip.split( /[ <,+]+/ )
        
        # add source for shortcuts (assumes relative path; if not issue warning/error)
        values << values[0] if values.size == 1
        
        # normalize all source paths (1..-1) /make full path/add template dir
        (1..values.size-1).each do |i|
          values[i] = "#{templatesdir}/#{values[i]}"
          logger.debug "  path[#{i}]=>#{values[i]}<"
        end
        
        manifest << values
      end      
    end

    manifest
  end

  def load_template( path ) 
    puts "  Loading template #{path}..."
    return File.read( path )
  end
  
  def render_template( content, the_binding )
    ERB.new( content ).result( the_binding )
  end

  def load_template_old_delete( name, builtin )
    
    if opts.has_includes? 
      opts.includes.each do |path|
        logger.debug "File.exists? #{path}/#{name}"
        
        if File.exists?( "#{path}/#{name}" ) then          
          puts "Loading custom template #{path}/#{name}..."
          return File.read( "#{path}/#{name}" )
        end
      end       
    end
    
    # fallback load builtin template packaged with gem
    load_builtin_template( builtin )
  end
  
  def with_output_path( dest, output_path )
    dest_full = File.expand_path( dest, output_path )
    logger.debug "dest_full=#{dest_full}"
      
    # make sure dest path exists
    dest_path = File.dirname( dest_full )
    logger.debug "dest_path=#{dest_path}"
    File.makedirs( dest_path ) unless File.directory? dest_path
    dest_full
  end

  def create_slideshow_templates
    logger.debug "manifest=#{opts.manifest}.gen"
    manifest = load_manifest( opts.manifest+".gen" )

    # expand output path in current dir and make sure output path exists
    outpath = File.expand_path( opts.output_path ) 
    logger.debug "outpath=#{outpath}"
    File.makedirs( outpath ) unless File.directory? outpath 

    manifest.each do |entry|
      dest   = entry[0]      
      source = entry[1]
                  
      puts "Copying to #{dest} from #{source}..."     
      File.copy( source, with_output_path( dest, outpath ) )
    end
    
    puts "Done."   
  end

  def create_slideshow( fn )

    logger.debug "manifest=#{opts.manifest}"
    manifest = load_manifest( opts.manifest )
    # pp manifest

    # expand output path in current dir and make sure output path exists
    outpath = File.expand_path( opts.output_path ) 
    logger.debug "outpath=#{outpath}"
    File.makedirs( outpath ) unless File.directory? outpath 

    dirname  = File.dirname( fn )    
    basename = File.basename( fn, '.*' )
    extname  = File.extname( fn )
    logger.debug "dirname=#{dirname}, basename=#{basename}, extname=#{extname}"

    # change working dir to sourcefile dir
    # todo: add a -c option to commandline? to let you set cwd?
    
    newcwd  = File.expand_path( dirname )
    oldcwd  = File.expand_path( Dir.pwd )
    
    unless newcwd == oldcwd then
      logger.debug "oldcwd=#{oldcwd}"
      logger.debug "newcwd=#{newcwd}"
      Dir.chdir newcwd
    end  

    puts "Preparing slideshow '#{basename}'..."
                
  if extname.empty? then
    extname  = ".textile"   # default to .textile 
    
    KNOWN_EXTNAMES.each do |e|
       logger.debug "File.exists? #{dirname}/#{basename}#{e}"
       if File.exists?( "#{dirname}/#{basename}#{e}" ) then         
          extname = e
          logger.debug "extname=#{extname}"
          break
       end
    end     
  end

  if KNOWN_MARKDOWN_EXTNAMES.include?( extname )
    @markup_type = :markdown
  else
    @markup_type = :textile
  end
  
  # shared variables for templates (binding)
  @content_for = {}  # reset content_for hash
  @name        = basename
  @headers     = @opts  # deprecate/remove: use headers method in template

  @session     = {}  # reset session hash for plugins/helpers

  inname  =  "#{dirname}/#{basename}#{extname}"

  logger.debug "inname=#{inname}"
    
  content_with_headers = File.read( inname )

  # todo: read headers before command line options (lets you override options using commandline switch)?
  
  # read source document; split off optional header from source
  # strip leading optional headers (key/value pairs) including optional empty lines

  read_headers = true
  content = ""
  
   # fix: allow comments in header too (#)

  content_with_headers.each do |line|
    if read_headers && line =~ /^\s*(\w[\w-]*)[ \t]*:[ \t]*(.*)/
      key = $1.downcase
      value = $2.strip
    
      logger.debug "  adding option: key=>#{key}< value=>#{value}<"
      opts.put( key, value )
    elsif line =~ /^\s*$/
      content << line  unless read_headers
    else
      read_headers = false
      content << line
    end
  end

  opts.set_defaults  
    
  # ruby note: .*? is non-greedy (shortest-possible) regex match
  content.gsub!(/__SKIP__.*?__END__/m, '')
  content.sub!(/__END__.*/m, '')
  
  # allow plugins/helpers; process source (including header) using erb
  
  # note: include is a ruby keyword; rename to __include__ so we can use it 
  content.gsub!( /<%=[ \t]*include/, '<%= __include__' )
  
  content =  ERB.new( content ).result( binding )
  
  # run pre-filters (built-in macros)
  # o replace {{{  w/ <pre class='code'>
  # o replace }}}  w/ </pre>
  content.gsub!( "{{{{{{", "<pre class='code'>_S9BEGIN_" )
  content.gsub!( "}}}}}}", "_S9END_</pre>" )  
  content.gsub!( "{{{", "<pre class='code'>" )
  content.gsub!( "}}}", "</pre>" )
  # restore escaped {{{}}} I'm sure there's a better way! Rubyize this! Anyone?
  content.gsub!( "_S9BEGIN_", "{{{" )
  content.gsub!( "_S9END_", "}}}" )

  # convert light-weight markup to hypertext
 
  content = case @markup_type
     when :markdown
      markdown_to_html( content )
    when :textile
      textile_to_html( content )
  end  

  # post-processing

  slide_counter = 0
  content2 = ''
  
  ## todo: move this to a filter (for easier reuse)
  
  # wrap h1's in slide divs; note use just <h1 since some processors add ids e.g. <h1 id='x'>
  content.each_line do |line|
     if line.include?( '<h1' ) then
        content2 << "\n\n</div>"  if slide_counter > 0
        content2 << "<div class='slide'>\n\n"
        slide_counter += 1
     end
     content2 << line
  end
  content2 << "\n\n</div>"   if slide_counter > 0

  manifest.each do |entry|
    outname = entry[0]
    if outname.include? '__file__' # process
      outname = outname.gsub( '__file__', basename )
      puts "Preparing #{outname}..."

      out = File.new( with_output_path( outname, outpath ), "w+" )

      out << render_template( load_template( entry[1] ), binding )
      
      if entry.size > 2 # more than one source file? assume header and footer with content added inbetween
        out << content2 
        out << render_template( load_template( entry[2] ), binding )
      end

      out.flush
      out.close

    else # just copy verbatim if target/dest has no __file__ in name
      dest   = entry[0]      
      source = entry[1]
            
      puts "Copying to #{dest} from #{source}..."     
      File.copy( source, with_output_path( dest, outpath ) )
    end
  end

  puts "Done."
end

def load_plugins
  
  # use lib folder unless we're in our very own folder 
  #  (that use lib for its core functionality), thus, use plugins instead  
  if( File.expand_path( File.dirname(__FILE__) ) == File.expand_path( 'lib' ) )
    pattern = 'plugins/**/*.rb'
  else
    pattern = 'lib/**/*.rb'
  end
  
  logger.debug "pattern=#{pattern}"
  
  Dir.glob( pattern ) do |plugin|
    begin
      puts "Loading plugins in '#{plugin}'..."
      require( plugin )
    rescue Exception => e
      puts "** error: failed loading plugins in '#{plugin}': #{e}"
    end
  end
end

def run( args )

  opt=OptionParser.new do |cmd|
    
    cmd.banner = "Usage: slideshow [options] name"
    
    #todo/fix: use -s5 option without optional hack? possible with OptionParser package/lib?
    # use -5 switch instead?
    cmd.on( '-s[OPTIONAL]', '--s5', 'S5 Compatible Slide Show' ) { opts.put( 's5', true ); opts.put( 'manifest', 's5.txt' ) }
    cmd.on( '-f[OPTIONAL]', '--fullerscreen', 'FullerScreen Compatible Slide Show' ) { opts.put( 'fuller', true ); opts.put( 'manifest', 'fullerscreen.txt' ) }
    # opts.on( "-s", "--style STYLE", "Select Stylesheet" ) { |s| $options[:style]=s }
    # opts.on( "-v", "--version", "Show version" )  {}
    
    cmd.on( '-g', '--generate',  'Generate Slide Show Templates' ) { opts.put( 'generate', true ) }
    
    cmd.on( '-o', '--output PATH', 'outputs to Path' ) { |s| opts.put( 'output', s ) }
    
    # use -d or -o  to select output directory for slideshow or slideshow templates?
    # cmd.on( '-d', '--directory DIRECTORY', 'Output Directory' ) { |s| opts.put( 'directory', s )  }
    # cmd.on( '-i', '--include PATH', 'Load Path' ) { |s| opts.put( 'include', s ) }

    # todo: find different letter for debug trace switch (use v for version?)
    cmd.on( "-v", "--verbose", "Show debug trace" )  do
       logger.datetime_format = "%H:%H:%S"
       logger.level = Logger::DEBUG      
    end

    cmd.on( "-t", "--template TEMPLATE", "Template Manifest" ) do |t|
      # todo: do some checks on passed in template argument
      opts.put( 'manifest', t )
    end
 
    cmd.on_tail( "-h", "--help", "Show this message" ) do
         puts 
         puts "Slide Show (S9) is a free web alternative to PowerPoint or KeyNote in Ruby"
         puts
         puts cmd.help
         puts
         puts "Examples:"
         puts "  slideshow microformats"
         puts "  slideshow microformats.textile"
         puts "  slideshow -s5 microformats       # S5 compatible"
         puts "  slideshow -f microformats        # FullerScreen compatible"
         puts "  slideshow -o slides microformats # Output slideshow to slides folder"
         puts 
         puts "More examles:"
         puts "  slideshow -g      # Generate slide show templates"
         puts "  slideshow -g -s5  # Generate S5 compatible slide show templates"
         puts "  slideshow -g -f   # Generate FullerScreen compatible slide show templates"
         puts
         puts "  slideshow -t s3.txt microformats     # Use custom slide show templates"
         puts
         puts "Further information:"
         puts "  http://slideshow.rubyforge.org" 
         exit
    end
  end

  opt.parse!( args )

  puts "Slide Show (S9) Version: #{VERSION} on Ruby #{RUBY_VERSION} (#{RUBY_RELEASE_DATE}) [#{RUBY_PLATFORM}]"

  if opts.generate?
    create_slideshow_templates
  else
    load_markdown_libs
    load_plugins  # check for optional plugins/extension in ./lib folder
    
    args.each { |fn| create_slideshow( fn ) }
  end
end

end # class Gen

def Slideshow.main
  Gen.new.run(ARGV)
end

end # module Slideshow

# load built-in (required) helpers/plugins
require "#{File.dirname(__FILE__)}/helpers/text_helper.rb"
require "#{File.dirname(__FILE__)}/helpers/capture_helper.rb"

# load built-in (optional) helpers/plugins
#   If a helper fails to load, simply ingnore it
#   If you want to use it install missing required gems e.g.:
#     gem install coderay
#     gem install ultraviolet etc.
BUILTIN_OPT_HELPERS = [
  "#{File.dirname(__FILE__)}/helpers/uv_helper.rb",
  "#{File.dirname(__FILE__)}/helpers/coderay_helper.rb",
]

BUILTIN_OPT_HELPERS.each do |helper| 
  begin
    require(helper)
  rescue Exception => e
    ;
  end
end

Slideshow.main if __FILE__ == $0