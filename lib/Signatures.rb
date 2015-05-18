require 'zlib'
require 'digest'

module Signatures

   def self.crc(filename)
      ret_crc32 = 0        # CRC initial value.
      max_buf_size = 8192  #buffer of 8 * 1024 byte.

      buf = [""].pack('A8192')
      File.open(filename,'rb') do |fp|
         while fp.read(max_buf_size, buf)
            ret_crc32 = Zlib.crc32(buf, ret_crc32)
         end
      end

      #puts " CRC32 for [ #{filename} ] IS [ #{ret_crc32} ] "
      return ret_crc32
   end

   def self.adler32(filename)
      max_buf_size = 8192  #buffer of 8 * 1024 byte.

      adler32 = Adler32.new

      buf = [""].pack('A8192')
      File.open(filename,'rb') do |fp|
         while fp.read(max_buf_size, buf)
            adler32.update(buf)
         end
      end

      return adler32.digest
   end

   def self.md5(filename)
      Digest::MD5.file(filename)
   end


   def self.dhash(image)
      img = `convert #{image} -quantize GRAY -colors 72 +dither -depth 8 -resize 9x8! - | convert - GRAY:-`
      #img.each_byte do |byte|
         #STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
      #end

      x = img.unpack('C*')

      signature = x.map.with_index { |e, i| ((i != 0) && (e > x[i-1])) ? 1 : 0 }.join('').to_i(2)

      #puts signature.to_s(16)
      return signature
   end

   def self.image_distance(x, y)
      (x ^ y).to_s(2).count('1')
   end


   ##
   # A Ruby implementation of the Adler-32 checksum algorithm,
   # which uses Ruby's own Zlib.adler32 class method.
   #
   # This Ruby implementation is a port of the Python adler32
   # implementation found in the pysync project. The Python reference
   # implementation, itself, was a port from zlib's adler32.c file.
   #
   # @see http://zlib.net/
   # @see http://freshmeat.net/projects/pysync/
   # @see https://github.com/byu/junkfood/blob/master/lib/junkfood/adler32.rb
   #
   class Adler32

      # largest prime smaller than 65536
      BASE = 65521
      # largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1
      NMAX = 5552
      # default initial s1 offset
      OFFS = 1

      ##
      # @param data (String) initial block of data to digest.
      #
      def initialize(data='')
         value = Zlib.adler32(data, OFFS)
         @s2, @s1 = (value >> 16) & 0xffff, value & 0xffff
         @count = data.length
      end

      ##
      # Adds another block of data to digest.
      #
      # @param data (String) block of data to digest.
      # @return (Fixnum) the updated digest.
      #
      def update(data)
         value = Zlib.adler32(data, (@s2 << 16) | @s1)
         @s2, @s1 = (value >> 16) & 0xffff, value & 0xffff
         @count = @count + data.length
         return self.digest
      end

      ##
      # @param x1 (Byte)
      # @param xn (Byte)
      # @return (Fixnum) the updated digest.
      #
      def rotate(x1, xn)
         @s1 = (@s1 - x1 + xn) % BASE
         @s2 = (@s2 - (@count * x1) + @s1 - OFFS) % BASE
         return self.digest
      end

      ##
      # @param b (Byte)
      # @return (Fixnum) the updated digest.
      #
      def rollin(b)
         @s1 = (@s1 + b) % BASE
         @s2 = (@s2 + @s1) % BASE
         @count = @count + 1
         return self.digest
      end

      ##
      # @param b (Byte)
      # @return (Fixnum) the updated digest.
      #
      def rollout(b)
         @s1 = (@s1 - b) % BASE
         @s2 = (@s2 - @count * b) % BASE
         @count = @count - 1
         return self.digest
      end

      ##
      # @return (Fixnum) the current Adler32 digest value.
      #
      def digest
         return (@s2 << 16) | @s1
      end
   end

end

if __FILE__ == $0
   beginning_time = Time.now
   signature = Signatures.crc(ARGV[0])
   end_time = Time.now
   puts "CRC: #{signature} Time elapsed #{(end_time - beginning_time)*1000} milliseconds"

   #beginning_time = Time.now
   #signature = Signatures.adler32(ARGV[0])
   #end_time = Time.now
   #puts "Adler32: #{signature} Time elapsed #{(end_time - beginning_time)*1000} milliseconds"

   #beginning_time = Time.now
   #signature = Signatures.md5(ARGV[0])
   #end_time = Time.now
   #puts "MD5: #{signature} Time elapsed #{(end_time - beginning_time)*1000} milliseconds"

   beginning_time = Time.now
   signature = Signatures.dhash(ARGV[0])
   end_time = Time.now
   puts "dHash: #{signature.to_s(16)} Time elapsed #{(end_time - beginning_time)*1000} milliseconds"
end
