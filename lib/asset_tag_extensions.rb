module AssetTagExtensions
  def self.included(base)
    base.send :alias_method_chain, :javascript_src_tag, :defer_options
    #base.send :alias_method_chain, :javascript_tag, :defer_options
    base.send :alias_method, :javascript_tag_without_defer_options, :javascript_tag
    base.send :alias_method, :javascript_include_tag_with_deferment, :javascript_include_tag_with_defer_options
  end

  # similar to javascript_include_tag but saves the files
  # to render at the bottom of the page
  # == Options
  # In additional to the +cache+ and the +recurring+ options the following are available
  # <tt>:javascript_style</tt> defaults to a standard script tag
  # * <tt>:append_to_head</tt> - using javascript, create a Script object with this source and append it to the head
  # * <tt>:document_write</tt> - using javascript, do a document.write on the javascript file
  # <tt>:defer</tt> - defaults to +true+.
  # * +false+ - renders the source to the document immediately
  # * +true+ - Adds the source to the list of javascript sources loaded at the end of the document
  # * <tt>:inline</tt> - adds the javascript file to the list of scripts loaded inline.
  #     This is the default when +javascript_style+ is set to +document_write+
  # * <tt>:on_load</tt> - adds the javascript file to load when the document is ready.
  #     This only makes sense for the +javascript_style+ options, and is the default if
  #     when set to +append_to_head+
  def javascript_include_tag_with_defer_options(*sources)
    options = sources.last.is_a?(Hash) ? sources.pop : {}
    javascript_include_tag(sources, options.reverse_merge(:defer => true))
  end

  # Adds options to rendering the javascript tag. Refer to the options in +javascript_include_tag_with_defer_options+
  def javascript_src_tag_with_defer_options(source, js_src_options={})
    options = js_src_options.stringify_keys

    defer_type =       options.delete('defer')
    javascript_style = options.delete('javascript_style')

    script = if javascript_style
      javascript_style_options = {
        :indent =>   options.delete('indent'),
        :protocol => options.delete('protocol')
      }

      # turn this into javascript
      source = case javascript_style.to_s
        when 'document_write' then document_write_script_file source, javascript_style_options
        when 'append_to_head' then append_to_head_script_file source, javascript_style_options
      end

      #the default defer type (when set to true) depends on the javascript_style
      defer_type_for_javascript_styles! javascript_style, defer_type

      #if it is not deferred, surround this with a javascript tag
      source = javascript_tag source unless defer_type
      source

    #otherwise build the normal javascript tag
    else
      javascript_src_tag_without_defer_options(source, options)
    end

    script = defer_javascript_file(script, defer_type=nil, options={}) if defer_type
    script
  end

  def defer_type_for_javascript_styles!(javascript_style, defer_type)#:nodoc:
    @@default_defer_type ||= {
      'document_write' => 'inline',
      'append_to_head' => 'on_load'
    }
    defer_type = @@default_defer_type[javascript_style.to_s] if defer_type.is_a?(TrueClass)
    defer_type
  end

  # Adds options to rendering the javascript tag when it is deferred
  def defer_javascript_file(script_code, defer_type=nil, options={})#:nodoc:
    case defer_type.to_s
    when 'on_load' then
      content_for :javascript_files_onload, script_code
    when 'inline' then
      inline_javascript_tag script_code
    else
      content_for( :javascript_files, "\n#{script_code}")
    end
    ''
  end

  # Specify inline javascript that will be written at the bottom of the page
  # +scripts+ - scripts to include inline
  #
  # ===Options
  # * <tt>on_load</tt>    This is executed when the page loads. Default is false.
  # * <tt>strip_tags</tt> When <tt>on_load</tt> is used, strip the <script..> tags off the input
  #
  #  script = javascript_tag("foo('doIt');");
  # This puts the javascript at the bottom of the page
  #  inline_javascript script
  # This loads the javascript when the document is loaded. Since it has tags, yank them
  #  inline_javascript script, :on_load => true, :strip_tags => true
  # Same as above
  #  inline_javascript "foo('doIt');", :on_load => true
  #
  # Use a block
  #
  #   inline_javascript :on_load => true do
  #     foo(<%= my_rails_var.inspect %>);
  #     //some other stuff
  #   end
  def inline_javascript(*scripts, &block)
    options = scripts.last.is_a?(Hash) ? scripts.pop : {}
    options.stringify_keys!
    options['defer'] ||= 'on_load' if options['on_load']

    content = if block_given?
      capture(&block)
    else
      "#{scripts.join("\n")}"
    end

    case options['defer'].to_s
      when 'jquery_onload', 'on_load' then
        strip_script_tags!( content ) if content =~ /^\s*<script/
        content << "\n" unless content =~ /\n$/
        content_for_with_top :jquery_onload, content, options
      else
        content = javascript_tag_without_defer_options(content, options['html_options']||{}) unless content =~ /^\s*<script/
        content_for_with_top :inline_javascripts, content, options
    end
    ''
  end
  #like content for but if :top => true, add the content to the top
  def content_for_with_top(name, content = nil, options = {}, &block)
    #raise options.inspect if content.try(:include?, 'oller')
    options.stringify_keys!
    ivar = "@content_for_#{name}"
    content = capture(&block) if block_given?
    all_content = options['top'] ? "#{content}#{instance_variable_get(ivar)}" : "#{instance_variable_get(ivar)}#{content}"
    instance_variable_set(ivar, all_content)
    nil
  end
  # like javascript_tag but defer this with
  # javascript_tag :defer => true do
  #   myClass.init();
  # end

  def javascript_tag_with_defer_options(content_or_options_with_block = nil, html_options = {}, &block)
    html_options = content_or_options_with_block if block_given? && content_or_options_with_block.is_a?(Hash)

    if html_options[:defer]
      inline_javascript_tag(content_or_options_with_block, html_options, &block)
    else
      javascript_tag_without_defer_options(content_or_options_with_block, html_options, &block)
    end
  end

  # Similar to javascript_tag, but moves the content to the bottom of the page
  # To use the on_load functionality, call inline_javascript instead
  def inline_javascript_tag(content_or_options_with_block = nil, html_options = {}, &block)
    html_options = content_or_options_with_block if block_given? && content_or_options_with_block.is_a?(Hash)

    html_options.stringify_keys!
    inline_options = {
      :defer => html_options.delete('defer') || true,
      :strip_tags => html_options.delete('strip_tags'),
      :html_options => html_options
    }
    inline_javascript(content_or_options_with_block, inline_options, &block)
  end

  # Append the source to the head of the document using javascript
  def append_to_head_script_file(script_code, options={})
    load_script_files(script_code) {|url| append_to_head_javascript_src(url, options) }
  end

  # Load the url or src of javascript tag into the document with a document write
  def document_write_script_file(script_code, options={})
    load_script_files(script_code) {|url| document_write_javascript_src(url, options) }
  end

  def load_script_files(script_code, options={}, &block)
    #script_code = javascript_include_tag(script_code) if options[:versioning]
    if script_code =~ /^\s*<script/
      url_from_javascript(script_code).inject('') do |output, url|
        output << yield(url)
      end
    else
      yield(script_code)
    end
  end

  # starting with a script tag, remove the src (url) field
  #   <script src="/javascripts/kashless/forms.js?1245447720" type="text/javascript">
  # becomes
  #   "/javascripts/kashless/forms.js?1245447720"
  def url_from_javascript(script_source)
    script_source.scan(/src\s*=\s*["']([^"']*)/).flatten
  end

  # strip javascript tags from string +content+
  # CDATA tags appended by rails are also stripped
  def strip_script_tags!(content)
    content.gsub!(/(^|\s*)<script[^>]*>(\s*\n)?(\/\/<\!\[CDATA\[\n)?/, '')
    content.gsub!(/(\n\/\/\]\]>)?\s*<\/script>\s*(\n|$)/, '')
    content
  end

  # Wrap the scripts in an jQuery onload tag
  # j_query_on_load_tag 'foo();'
  # j_query_on_load_tag { blah(<%=blah%>); }
  def j_query_on_load_tag(*scripts, &block)
    options = scripts.last.is_a?(Hash) ? scripts.pop : {}

    #strangely 6 * ' ' wont work here
    indent = ''
    0.upto(options['indent'].to_i) {|i| indent << ' '}


    js_code = if scripts.any?
      scripts.compact.join("\n#{indent}    ")
    else
      capture(&block)
    end

    javascript_code=<<-EOS
#{indent}(function ($) {
#{indent}  $(function() {
#{indent}    #{js_code}
#{indent}  });
#{indent}})(jQuery);
EOS
  end

  # returns the javascript code to append a javascript file specified by +url+ 
  # to the head of the document
  # === Options
  # * <tt>:indent</tt> - Number of spaces to indent each line
  # * <tt>:protocol</tt> - explained in +url_from_javascript_tag_options+
  def append_to_head_javascript_src(url, options={})
    options.stringify_keys!

    logger.debug "APPEND:#{url.inspect}"

    indent = ' ' * options['indent'].to_i
    variable_name = "e_#{Time.now.strftime("%Y%m%d%H%M%S")}_#{rand(500)}"
script=<<-EOS
/*#{options.inspect} */
#{indent}var #{variable_name} = document.createElement("script");
#{indent}#{variable_name}.src = "#{url_from_javascript_tag_options(url, options['protocol'])}";
#{indent}#{variable_name}.type="text/javascript";
#{indent}document.getElementsByTagName("head")[0].appendChild(#{variable_name});
EOS
  end

  # returns the javascript code to add the javascript file specified by +url+ 
  # with document.write
  # +url+ - can be a string, hash or route
  # === Options
  # * <tt>:indent</tt> - Number of spaces to indent each line
  # * <tt>:protocol</tt> - explained in +url_from_javascript_tag_options+
  def document_write_javascript_src(url, options={})
    options.stringify_keys!

    string_url = url_from_javascript_tag_options(url, options['protocol'])
    script = ' ' * options['indent'].to_i
    script <<  "document.write(unescape(\"%3Cscript src='#{string_url}' type='text/javascript'%3E%3C/script%3E\"));\n";
    script
  end

  # Convert javascript source to a url. If the source is external (contains http:// or https://)
  # then the <tt>:protocol</tt> option can be used to force the protocol
  # <tt>protocol</tt> can be one of the following
  # *<tt>:http</tt> - force the javascript to http
  # *<tt>:https</tt> - force the javascript to https
  # *<tt>:document</tt> - use the same protocol as the document. If this has a controller and a
  #  request then the request is used. If not, then javascript is used to determine the document
  #  location
  def url_from_javascript_tag_options(source, protocol)

    logger.debug "SOURCE: #{source.inspect}"
    url = compute_public_path(source, 'javascripts', 'js', true)

    if url =~ %r{^[-a-z]+://} && protocol
      if protocol.to_s == 'document'
        protocol = if @controller.request && @controller.request.protocol
          @controller.request.protocol
        else
          %Q(" + (("https:" == document.location.protocol) ? "https" : "http") + ")
        end
      end

      protocol << '://' unless protocol =~ %r{://$}
      url.gsub!(/^[-a-z]+:/, protocol)
    end
    url
  end

  # include the javascripts that are deferred
  def render_deferred_javascript_files
    #write any deffered javascript files
    return '' if @content_for_javascript_files.blank?
    js_code = "\n<!-- DEFFERRED Javascripts -->\n#{@content_for_javascript_files}"
  end

  # Render any inline javascripts
  def render_inline_javascripts
    #write out any inline javascript
    return '' if @content_for_inline_javascripts.blank?
    js_code = "\n<!-- Inline Javascripts -->\n#{@content_for_inline_javascripts}"
  end

  # Render the jquery on load (page loaded) javascripts
  def render_inline_on_load_javascripts
    return '' if @content_for_jquery_onload.blank? && @content_for_javascript_files_onload.blank?
    js_code = "\n<!-- DEFFERRED On page load Javascripts -->\n"
    on_load_scripts = [  ]
    #write the onload inline javascripts
    on_load_scripts << @content_for_jquery_onload           if @content_for_jquery_onload
    #write the javascript files which are jammed into the document head
    on_load_scripts << @content_for_javascript_files_onload if @content_for_javascript_files_onload
    js_code << javascript_tag(j_query_on_load_tag(on_load_scripts)) unless on_load_scripts.blank?
    js_code
  end

  # Render all types of deffered javascripts
  def render_deferred_javascript_tags
    # First write the onload inline javascripts
    js_code = ''
    js_code << render_deferred_javascript_files
    js_code << render_inline_javascripts
    js_code << render_inline_on_load_javascripts
    js_code
  end
end

unless ActionView::Base.method_defined?(:inline_javascript_tag)
  ActionView::Base.send :include, AssetTagExtensions
end
