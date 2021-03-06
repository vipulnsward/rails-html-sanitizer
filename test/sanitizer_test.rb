require "minitest/autorun"
require "rails-html-sanitizer"
require "rails/dom/testing/assertions/dom_assertions"

class SanitizersTest < Minitest::Test
  include Rails::Dom::Testing::Assertions::DomAssertions

  def setup
    @sanitizer = nil # used by assert_sanitizer
  end

  def test_sanitizer_sanitize_raises_not_implemented_error
    assert_raises NotImplementedError do
      Rails::Html::Sanitizer.new.sanitize('')
    end
  end

  class TestSanitizer < Rails::Html::Sanitizer
    def sanitize(html, options = {})
      remove_xpaths(html, options[:xpaths])
    end
  end

  def test_remove_xpaths_removes_an_xpath
    sanitizer = TestSanitizer.new
    html = %(<h1>hello <script>code!</script></h1>)
    assert_equal %(<h1>hello </h1>), sanitizer.sanitize(html, xpaths: %w(.//script))
  end

  def test_remove_xpaths_removes_all_occurences_of_xpath
    sanitizer = TestSanitizer.new
    html = %(<section><header><script>code!</script></header><p>hello <script>code!</script></p></section>)
    assert_equal %(<section><header></header><p>hello </p></section>), sanitizer.sanitize(html, xpaths: %w(.//script))
  end

  def test_remove_xpaths_called_with_faulty_xpath
    sanitizer = TestSanitizer.new
    assert_raises Nokogiri::XML::XPath::SyntaxError do
      sanitizer.sanitize('<h1>hello<h1>', xpaths: %w(..faulty_xpath))
    end
  end

  def test_remove_xpaths_called_with_xpath_string
    sanitizer = TestSanitizer.new
    assert_equal '', sanitizer.sanitize('<a></a>', xpaths: './/a')
  end

  def test_remove_xpaths_called_with_enumerable_xpaths
    sanitizer = TestSanitizer.new
    assert_equal '', sanitizer.sanitize('<a><span></span></a>', xpaths: %w(.//a .//span))
  end

  def test_remove_xpaths_called_with_string_returns_string
    sanitizer = TestSanitizer.new
    assert_equal '<a></a>', sanitizer.sanitize('<a></a>', xpaths: [])
  end

  def test_remove_xpaths_called_with_fragment_returns_fragment
    sanitizer = TestSanitizer.new
    fragment = sanitizer.sanitize(Loofah.fragment('<a></a>'), xpaths: [])
    assert_kind_of Loofah::HTML::DocumentFragment, fragment
  end

  def test_strip_tags_with_quote
    sanitizer = Rails::Html::FullSanitizer.new
    string    = '<" <img src="trollface.gif" onload="alert(1)"> hi'

    assert_equal ' hi', sanitizer.sanitize(string)
  end

  def test_strip_tags_pending
    skip "Pending. These methods don't pass."
    sanitizer = Rails::Html::FullSanitizer.new

    # Loofah doesn't see any elements in this
    # Actual: ""
    assert_equal("<<<bad html", sanitizer.sanitize("<<<bad html"))

    # Actual: "Weia onclick='alert(document.cookie);'/&gt;rdos"
    assert_equal("Weirdos", sanitizer.sanitize("Wei<<a>a onclick='alert(document.cookie);'</a>/>rdos"))

    # Loofah strips newlines.
    # Actual: "This is a test.It no longer contains any HTML."
    assert_equal(
    %{This is a test.\n\n\nIt no longer contains any HTML.\n}, sanitizer.sanitize(
    %{<title>This is <b>a <a href="" target="_blank">test</a></b>.</title>\n\n<!-- it has a comment -->\n\n<p>It no <b>longer <strong>contains <em>any <strike>HTML</strike></em>.</strong></b></p>\n}))

    # Removes comment.
    # Actual: "This is "
    assert_equal "This is <-- not\n a comment here.", sanitizer.sanitize("This is <-- not\n a comment here.")

    # Leaves part of a CDATA section
    # Actual: "This has a ]]&gt; here."
    assert_equal "This has a  here.", sanitizer.sanitize("This has a <![CDATA[<section>]]> here.")

    # Actual: "This has an unclosed ]] here..."
    assert_equal "This has an unclosed ", sanitizer.sanitize("This has an unclosed <![CDATA[<section>]] here...")

    # Fails on the blank string.
    # Actual: ''
    [nil, '', '   '].each { |blank| assert_equal blank, sanitizer.sanitize(blank) }
  end

  def test_strip_tags
    sanitizer = Rails::Html::FullSanitizer.new

    assert_equal("Dont touch me", sanitizer.sanitize("Dont touch me"))
    assert_equal("This is a test.", sanitizer.sanitize("<p>This <u>is<u> a <a href='test.html'><strong>test</strong></a>.</p>"))

    assert_equal("", sanitizer.sanitize("<<<bad html>"))

    assert_equal("This is a test.", sanitizer.sanitize("This is a test."))

    assert_equal "This has a  here.", sanitizer.sanitize("This has a <!-- comment --> here.")
    assert_equal "This is a frozen string with no tags", sanitizer.sanitize("This is a frozen string with no tags".freeze)
  end

  def test_strip_links_pending
    skip "Pending. Extracted from test_strip_links."
    sanitizer = Rails::Html::LinkSanitizer.new

    # Only one of the a-tags are parsed here
    # Actual: "a href='hello'&gt;all <b>day</b> long/a&gt;"
    assert_equal "all <b>day</b> long", sanitizer.sanitize("<<a>a href='hello'>all <b>day</b> long<</A>/a>")

    # Loofah reads this as '<a></a>' which the LinkSanitizer removes
    # Actual: ""
    assert_equal "<a<a", sanitizer.sanitize("<a<a")
  end

  def test_strip_links
    sanitizer = Rails::Html::LinkSanitizer.new
    assert_equal "Dont touch me", sanitizer.sanitize("Dont touch me")
    assert_equal "on my mind\nall day long", sanitizer.sanitize("<a href='almost'>on my mind</a>\n<A href='almost'>all day long</A>")
    assert_equal "0wn3d", sanitizer.sanitize("<a href='http://www.rubyonrails.com/'><a href='http://www.rubyonrails.com/' onlclick='steal()'>0wn3d</a></a>")
    assert_equal "Magic", sanitizer.sanitize("<a href='http://www.rubyonrails.com/'>Mag<a href='http://www.ruby-lang.org/'>ic")
    assert_equal "FrrFox", sanitizer.sanitize("<href onlclick='steal()'>FrrFox</a></href>")
    assert_equal "My mind\nall <b>day</b> long", sanitizer.sanitize("<a href='almost'>My mind</a>\n<A href='almost'>all <b>day</b> long</A>")

  end

  def test_sanitize_form
    assert_sanitized "<form action=\"/foo/bar\" method=\"post\"><input></form>", ''
  end

  def test_sanitize_plaintext
    raw = "<plaintext><span>foo</span></plaintext>"
    assert_sanitized raw, "<span>foo</span>"
  end

  def test_sanitize_script
    assert_sanitized "a b c<script language=\"Javascript\">blah blah blah</script>d e f", "a b cd e f"
  end

  def test_sanitize_js_handlers
    raw = %{onthis="do that" <a href="#" onclick="hello" name="foo" onbogus="remove me">hello</a>}
    assert_sanitized raw, %{onthis="do that" <a href="#" name="foo">hello</a>}
  end

  def test_sanitize_javascript_href
    raw = %{href="javascript:bang" <a href="javascript:bang" name="hello">foo</a>, <span href="javascript:bang">bar</span>}
    assert_sanitized raw, %{href="javascript:bang" <a name="hello">foo</a>, <span>bar</span>}
  end

  def test_sanitize_image_src
    raw = %{src="javascript:bang" <img src="javascript:bang" width="5">foo</img>, <span src="javascript:bang">bar</span>}
    assert_sanitized raw, %{src="javascript:bang" <img width="5">foo</img>, <span>bar</span>}
  end

  Rails::Html::WhiteListSanitizer.allowed_tags.each do |tag_name|
    define_method "test_should_allow_#{tag_name}_tag" do
      assert_sanitized "start <#{tag_name} title=\"1\" onclick=\"foo\">foo <bad>bar</bad> baz</#{tag_name}> end", %(start <#{tag_name} title="1">foo bar baz</#{tag_name}> end)
    end
  end

  def test_should_allow_anchors
    assert_sanitized %(<a href="foo" onclick="bar"><script>baz</script></a>), %(<a href=\"foo\">baz</a>)
  end

  def test_video_poster_sanitization
    assert_sanitized %(<video src="videofile.ogg" autoplay  poster="posterimage.jpg"></video>), %(<video src="videofile.ogg" poster="posterimage.jpg"></video>)
    assert_sanitized %(<video src="videofile.ogg" poster=javascript:alert(1)></video>), %(<video src="videofile.ogg"></video>)
  end

  # RFC 3986, sec 4.2
  def test_allow_colons_in_path_component
    assert_sanitized("<a href=\"./this:that\">foo</a>")
  end

  %w(src width height alt).each do |img_attr|
    define_method "test_should_allow_image_#{img_attr}_attribute" do
      assert_sanitized %(<img #{img_attr}="foo" onclick="bar" />), %(<img #{img_attr}="foo" />)
    end
  end

  def test_should_handle_non_html
    assert_sanitized 'abc'
  end

  def test_should_handle_blank_text
    assert_sanitized nil
    assert_sanitized ''
  end

  def test_should_allow_custom_tags
    text = "<u>foo</u>"
    sanitizer = Rails::Html::WhiteListSanitizer.new
    assert_equal(text, sanitizer.sanitize(text, tags: %w(u)))
  end

  def test_should_allow_only_custom_tags
    text = "<u>foo</u> with <i>bar</i>"
    sanitizer = Rails::Html::WhiteListSanitizer.new
    assert_equal("<u>foo</u> with bar", sanitizer.sanitize(text, tags: %w(u)))
  end

  def test_should_allow_custom_tags_with_attributes
    text = %(<blockquote cite="http://example.com/">foo</blockquote>)
    sanitizer = Rails::Html::WhiteListSanitizer.new
    assert_equal(text, sanitizer.sanitize(text))
  end

  def test_should_allow_custom_tags_with_custom_attributes
    text = %(<blockquote foo="bar">Lorem ipsum</blockquote>)
    sanitizer = Rails::Html::WhiteListSanitizer.new
    assert_equal(text, sanitizer.sanitize(text, attributes: ['foo']))
  end

  def test_should_raise_argument_error_if_tags_is_not_enumerable
    sanitizer = Rails::Html::WhiteListSanitizer.new
    assert_raises(ArgumentError) do
      sanitizer.sanitize('<a>some html</a>', tags: 'foo')
    end
  end

  def test_should_raise_argument_error_if_attributes_is_not_enumerable
    sanitizer = Rails::Html::WhiteListSanitizer.new

    assert_raises(ArgumentError) do
      sanitizer.sanitize('<a>some html</a>', attributes: 'foo')
    end
  end

  def test_should_not_accept_non_loofah_inheriting_scrubber
    sanitizer = Rails::Html::WhiteListSanitizer.new
    scrubber = Object.new
    def scrubber.scrub(node); node.name = 'h1'; end

    assert_raises Loofah::ScrubberNotFound do
      sanitizer.sanitize('<a>some html</a>', scrubber: scrubber)
    end
  end

  def test_should_accept_loofah_inheriting_scrubber
    sanitizer = Rails::Html::WhiteListSanitizer.new
    scrubber = Loofah::Scrubber.new
    def scrubber.scrub(node); node.name = 'h1'; end

    html = "<script>hello!</script>"
    assert_equal "<h1>hello!</h1>", sanitizer.sanitize(html, scrubber: scrubber)
  end

  def test_should_accept_loofah_scrubber_that_wraps_a_block
    sanitizer = Rails::Html::WhiteListSanitizer.new
    scrubber = Loofah::Scrubber.new { |node| node.name = 'h1' }
    html = "<script>hello!</script>"
    assert_equal "<h1>hello!</h1>", sanitizer.sanitize(html, scrubber: scrubber)
  end

  def test_custom_scrubber_takes_precedence_over_other_options
    sanitizer = Rails::Html::WhiteListSanitizer.new
    scrubber = Loofah::Scrubber.new { |node| node.name = 'h1' }
    html = "<script>hello!</script>"
    assert_equal "<h1>hello!</h1>", sanitizer.sanitize(html, scrubber: scrubber, tags: ['foo'])
  end

  [%w(img src), %w(a href)].each do |(tag, attr)|
    define_method "test_should_strip_#{attr}_attribute_in_#{tag}_with_bad_protocols" do
      assert_sanitized %(<#{tag} #{attr}="javascript:bang" title="1">boo</#{tag}>), %(<#{tag} title="1">boo</#{tag}>)
    end
  end

  def test_should_block_script_tag
    assert_sanitized %(<SCRIPT\nSRC=http://ha.ckers.org/xss.js></SCRIPT>), ""
  end

  def test_should_not_fall_for_xss_image_hack_pending
    skip "Pending."

    # Actual: "<img>alert(\"XSS\")\"&gt;"
    assert_sanitized %(<IMG """><SCRIPT>alert("XSS")</SCRIPT>">), "<img>"
  end

  [%(<IMG SRC="javascript:alert('XSS');">),
   %(<IMG SRC=javascript:alert('XSS')>),
   %(<IMG SRC=JaVaScRiPt:alert('XSS')>),
   %(<IMG SRC=javascript:alert(&quot;XSS&quot;)>),
   %(<IMG SRC=javascript:alert(String.fromCharCode(88,83,83))>),
   %(<IMG SRC=&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;&#97;&#108;&#101;&#114;&#116;&#40;&#39;&#88;&#83;&#83;&#39;&#41;>),
   %(<IMG SRC=&#0000106&#0000097&#0000118&#0000097&#0000115&#0000099&#0000114&#0000105&#0000112&#0000116&#0000058&#0000097&#0000108&#0000101&#0000114&#0000116&#0000040&#0000039&#0000088&#0000083&#0000083&#0000039&#0000041>),
   %(<IMG SRC=&#x6A&#x61&#x76&#x61&#x73&#x63&#x72&#x69&#x70&#x74&#x3A&#x61&#x6C&#x65&#x72&#x74&#x28&#x27&#x58&#x53&#x53&#x27&#x29>),
   %(<IMG SRC="jav\tascript:alert('XSS');">),
   %(<IMG SRC="jav&#x09;ascript:alert('XSS');">),
   %(<IMG SRC="jav&#x0A;ascript:alert('XSS');">),
   %(<IMG SRC="jav&#x0D;ascript:alert('XSS');">),
   %(<IMG SRC=" &#14;  javascript:alert('XSS');">),
   %(<IMG SRC="javascript&#x3a;alert('XSS');">),
   %(<IMG SRC=`javascript:alert("RSnake says, 'XSS'")`>)].each_with_index do |img_hack, i|
    define_method "test_should_not_fall_for_xss_image_hack_#{i+1}" do
      assert_sanitized img_hack, "<img>"
    end
  end

  def test_should_sanitize_tag_broken_up_by_null
    skip "Pending."

    # Loofah parses this to an <scr> tag and removes it.
    # So actual is an empty string"
    assert_sanitized %(<SCR\0IPT>alert(\"XSS\")</SCR\0IPT>), "alert(\"XSS\")"
  end

  def test_should_sanitize_invalid_script_tag
    assert_sanitized %(<SCRIPT/XSS SRC="http://ha.ckers.org/xss.js"></SCRIPT>), ""
  end

  def test_should_sanitize_script_tag_with_multiple_open_brackets
    skip "Pending."

    # Actual: "alert(\"XSS\");//"
    assert_sanitized %(<<SCRIPT>alert("XSS");//<</SCRIPT>), "&lt;"

    # Actual: ""
    assert_sanitized %(<iframe src=http://ha.ckers.org/scriptlet.html\n<a), %(&lt;a)
  end

  def test_should_sanitize_unclosed_script
    assert_sanitized %(<SCRIPT SRC=http://ha.ckers.org/xss.js?<B>), ""
  end

  def test_should_sanitize_half_open_scripts
    assert_sanitized %(<IMG SRC="javascript:alert('XSS')"), "<img>"
  end

  def test_should_not_fall_for_ridiculous_hack
    img_hack = %(<IMG\nSRC\n=\n"\nj\na\nv\na\ns\nc\nr\ni\np\nt\n:\na\nl\ne\nr\nt\n(\n'\nX\nS\nS\n'\n)\n"\n>)
    assert_sanitized img_hack, "<img>"
  end

  def test_should_sanitize_attributes
    assert_sanitized %(<SPAN title="'><script>alert()</script>">blah</SPAN>), %(<span title="#{CGI.escapeHTML "'><script>alert()</script>"}">blah</span>)
  end

  def test_should_sanitize_illegal_style_properties
    raw      = %(display:block; position:absolute; left:0; top:0; width:100%; height:100%; z-index:1; background-color:black; background-image:url(http://www.ragingplatypus.com/i/cam-full.jpg); background-x:center; background-y:center; background-repeat:repeat;)
    expected = %(display: block; width: 100%; height: 100%; background-color: black; background-x: center; background-y: center;)
    assert_equal expected, sanitize_css(raw)
  end

  def test_should_sanitize_with_trailing_space
    raw = "display:block; "
    expected = "display: block;"
    assert_equal expected, sanitize_css(raw)
  end

  def test_should_sanitize_xul_style_attributes
    raw = %(-moz-binding:url('http://ha.ckers.org/xssmoz.xml#xss'))
    assert_equal '', sanitize_css(raw)
  end

  def test_should_sanitize_invalid_tag_names
    assert_sanitized(%(a b c<script/XSS src="http://ha.ckers.org/xss.js"></script>d e f), "a b cd e f")
  end

  def test_should_sanitize_non_alpha_and_non_digit_characters_in_tags
    assert_sanitized('<a onclick!#$%&()*~+-_.,:;?@[/|\]^`=alert("XSS")>foo</a>', "<a>foo</a>")
  end

  def test_should_sanitize_invalid_tag_names_in_single_tags
    assert_sanitized('<img/src="http://ha.ckers.org/xss.js"/>', "<img />")
  end

  def test_should_sanitize_img_dynsrc_lowsrc
    assert_sanitized(%(<img lowsrc="javascript:alert('XSS')" />), "<img />")
  end

  def test_should_sanitize_div_background_image_unicode_encoded
    raw = %(background-image:\0075\0072\006C\0028'\006a\0061\0076\0061\0073\0063\0072\0069\0070\0074\003a\0061\006c\0065\0072\0074\0028.1027\0058.1053\0053\0027\0029'\0029)
    assert_equal '', sanitize_css(raw)
  end

  def test_should_sanitize_div_style_expression
    raw = %(width: expression(alert('XSS'));)
    assert_equal '', sanitize_css(raw)
  end

  def test_should_sanitize_across_newlines
    raw = %(\nwidth:\nexpression(alert('XSS'));\n)
    assert_equal '', sanitize_css(raw)
  end

  def test_should_sanitize_img_vbscript
    assert_sanitized %(<img src='vbscript:msgbox("XSS")' />), '<img />'
  end

  def test_should_sanitize_cdata_section
    skip "Pending."

    # Expected: "&lt;![CDATA[&lt;span&gt;section&lt;/span&gt;]]&gt;"
    # Actual: "section]]&gt;"
    assert_sanitized "<![CDATA[<span>section</span>]]>", "&lt;![CDATA[&lt;span>section&lt;/span>]]>"
  end

  def test_should_sanitize_unterminated_cdata_section
    skip "Pending."

    # Expected: "&lt;![CDATA[&lt;span&gt;neverending...]]&gt;"
    # Actual: "neverending..."
    assert_sanitized "<![CDATA[<span>neverending...", "&lt;![CDATA[&lt;span>neverending...]]>"
  end

  def test_should_not_mangle_urls_with_ampersand
     assert_sanitized %{<a href=\"http://www.domain.com?var1=1&amp;var2=2\">my link</a>}
  end

  def test_should_sanitize_neverending_attribute
    assert_sanitized "<span class=\"\\", "<span class=\"\\\">"
  end

  def test_x03a
    assert_sanitized %(<a href="javascript&#x3a;alert('XSS');">), "<a>"
    assert_sanitized %(<a href="javascript&#x003a;alert('XSS');">), "<a>"
    assert_sanitized %(<a href="http&#x3a;//legit">), %(<a href="http://legit">)
    assert_sanitized %(<a href="javascript&#x3A;alert('XSS');">), "<a>"
    assert_sanitized %(<a href="javascript&#x003A;alert('XSS');">), "<a>"
    assert_sanitized %(<a href="http&#x3A;//legit">), %(<a href="http://legit">)
  end

protected
  def assert_sanitized(input, expected = nil)
    @sanitizer ||= Rails::Html::WhiteListSanitizer.new
    if input
      assert_dom_equal expected || input, @sanitizer.sanitize(input)
    else
      assert_nil @sanitizer.sanitize(input)
    end
  end

  def sanitize_css(input)
    (@sanitizer ||= Rails::Html::WhiteListSanitizer.new).sanitize_css(input)
  end
end
