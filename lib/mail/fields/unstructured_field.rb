# encoding: utf-8
# frozen_string_literal: true
require 'mail/utilities'

module Mail
  # Provides access to an unstructured header field
  #
  # ===Per RFC 2822:
  #  2.2.1. Unstructured Header Field Bodies
  #
  #     Some field bodies in this standard are defined simply as
  #     "unstructured" (which is specified below as any US-ASCII characters,
  #     except for CR and LF) with no further restrictions.  These are
  #     referred to as unstructured field bodies.  Semantically, unstructured
  #     field bodies are simply to be treated as a single line of characters
  #     with no further processing (except for header "folding" and
  #     "unfolding" as described in section 2.2.3).
  class UnstructuredField < CommonField #:nodoc:
    def initialize(name, value, charset = nil)
      if value.is_a?(Array)
        # Probably has arrived here from a failed parse of an AddressList Field
        value = value.join(', ')

      # Mark UTF-8 strings parsed from ASCII-8BIT
      elsif value.respond_to?(:force_encoding) && value.encoding == Encoding::ASCII_8BIT
        utf8 = value.dup.force_encoding(Encoding::UTF_8)
        value = utf8 if utf8.valid_encoding?
      end

      charset ||=
        if value.respond_to?(:encoding)
          value.encoding
        end

      super name, value.to_s, charset
    end

    # An unstructured field does not parse
    def parse
      self
    end

    private

    def do_encode
      if value && !value.empty?
        "#{wrapped_value}\r\n"
      else
        ''
      end
    end

    def do_decode
      Utilities.blank?(value) ? nil : Encodings.decode_encode(value, :decode)
    end

    # 2.2.3. Long Header Fields
    #
    #  Each header field is logically a single line of characters comprising
    #  the field name, the colon, and the field body.  For convenience
    #  however, and to deal with the 998/78 character limitations per line,
    #  the field body portion of a header field can be split into a multiple
    #  line representation; this is called "folding".  The general rule is
    #  that wherever this standard allows for folding white space (not
    #  simply WSP characters), a CRLF may be inserted before any WSP.  For
    #  example, the header field:
    #
    #          Subject: This is a test
    #
    #  can be represented as:
    #
    #          Subject: This
    #           is a test
    #
    #  Note: Though structured field bodies are defined in such a way that
    #  folding can take place between many of the lexical tokens (and even
    #  within some of the lexical tokens), folding SHOULD be limited to
    #  placing the CRLF at higher-level syntactic breaks.  For instance, if
    #  a field body is defined as comma-separated values, it is recommended
    #  that folding occur after the comma separating the structured items in
    #  preference to other places where the field could be folded, even if
    #  it is allowed elsewhere.
    def wrapped_value # :nodoc:
      wrap_lines(name, fold("#{name}: ".length))
    end

    # 6.2. Display of 'encoded-word's
    #
    #  When displaying a particular header field that contains multiple
    #  'encoded-word's, any 'linear-white-space' that separates a pair of
    #  adjacent 'encoded-word's is ignored.  (This is to allow the use of
    #  multiple 'encoded-word's to represent long strings of unencoded text,
    #  without having to separate 'encoded-word's where spaces occur in the
    #  unencoded text.)
    def wrap_lines(name, folded_lines)
      result = ["#{name}: #{folded_lines.shift}"]
      result.concat(folded_lines)
      result.join("\r\n\s")
    end

    def fold(prepend = 0) # :nodoc:
      encoding       = normalized_encoding
      decoded_string = decoded.to_s
      should_encode  = !decoded_string.ascii_only?
      # If a header with only ASCII characters exceeds 998 characters without whitespace,
      # it can be safely folded by encoding it.
      if !should_encode && decoded_string.split(/[ \t]/).any? { |word| word.length > 900 }
        should_encode = true
      end
      if should_encode
        first = true
        words = decoded_string.split(/[ \t]/).map do |word|
          if first
            first = !first
          else
            word = " #{word}"
          end
          # A UTF-8 character can take up to 4 bytes, which becomes 12 bytes when encoded with QP.
          # 70 characters is safe for the 998-byte limit.
          word.scan(/.{1,70}/)
        end.flatten
      else
        words = decoded_string.split(/[ \t]/)
      end

      folded_lines   = []
      while !words.empty?
        limit = 78 - prepend
        limit = limit - 7 - encoding.length if should_encode
        line = String.new
        first_word = true
        while !words.empty?
          break unless word = words.first.dup

          # Convert on 1.9+ only since we aren't sure of the current
          # charset encoding on 1.8. We'd need to track internal/external
          # charset on each field.
          if charset && word.respond_to?(:encoding)
            word = Encodings.transcode_charset(word, word.encoding, charset)
          end

          word = encode(word) if should_encode
          word = encode_crlf(word)
          # Skip to next line if we're going to go past the limit
          # Unless this is the first word, in which case we're going to add it anyway
          break if !line.empty? && (line.length + word.length + 1 > limit)
          # Remove the word from the queue ...
          words.shift
          # Add word separator
          if first_word
            first_word = false
          else
            line << " " if !should_encode
          end

          # ... add it in encoded form to the current line
          line << word
        end
        # Encode the line if necessary
        line = "=?#{encoding}?Q?#{line}?=" if should_encode
        # Add the line to the output and reset the prepend
        folded_lines << line
        prepend = 0
      end
      folded_lines
    end

    def encode(value)
      value = [value].pack(Constants::CAPITAL_M).gsub(Constants::EQUAL_LF, Constants::EMPTY)
      value.gsub!(/"/,  '=22')
      value.gsub!(/\(/, '=28')
      value.gsub!(/\)/, '=29')
      value.gsub!(/\?/, '=3F')
      value.gsub!(/_/,  '=5F')
      value.gsub!(/ /,  '_')
      value
    end

    def encode_crlf(value)
      value.gsub!(Constants::CR, Constants::CR_ENCODED)
      value.gsub!(Constants::LF, Constants::LF_ENCODED)
      value
    end

    def normalized_encoding
      charset.to_s.upcase.gsub('_', '-')
    end
  end
end
