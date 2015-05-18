# encoding: US-ASCII 
# DONT DELETE THE ABOVE LINE

require 'date'
require 'pp'
require 'zlib'
require 'date'



class String

  # We implement magic number type by using a lookup hash.
  # This is fast enough for our needs; it could be optimized.
  #
  # The key is a string that encodes the first bits.
  # The value is a symbol that indicates the magic type.
  #
  # See:
  #  - IO#magic_number_type
  #  - File.magic_number_type
  #
  # Quirks:
  #   - JPEG adjustment:
  #     - Some cameras put JPEG Exif data in bytes 3 & 4,
  #       so we only check the first two bytes of a JPEG.
  #   - TIFF has two possible matches:
  #     - II.. Intel little ending ("II2A00")
  #     - MM.. Motorola big endian ("MM002A")
  #
  # TODO change from hash implementation to binary tree
  #
  MagicNumberTypeHash = {
    "GIF8" => { :media => :gif, :type => :image },
    ["FFD8"].pack('H*') => { :media => :jpeg, :type => :image },
    ["89504E470D0A1A0A"].pack('H*') => { :media => :png, :type => :image },
    "II" + ["2A00"].pack('H*') => { :media => :tiff, :type => :image },  # II means Intel format, then 42 little-endian
    "MM" + ["002A"].pack('H*') => { :media => :tiff, :type => :image },  # MM means Motorola format, then 42 big-endian
    "\x00\x00\x00\x14ftypisom" => { :media => :iso_base_media, :type => :video },  # ISO Base Media file (MPEG-4) v1
    "\x00\x00\x00\x20ftypisom" => { :media => :iso_base_media, :type => :video },  # ISO Base Media file (MPEG-4) v1
    "\x00\x00\x00\x14pnot" => { :media => :quicktime_movie, :type => :video },
    "\x00\x00\x00\x14ftypqt" => { :media => :quicktime_movie, :type => :video },
    "\x00\x00\x00\x18ftypqt" => { :media => :quicktime_movie, :type => :video },
    "\x00\x00\x00\x20ftypqt" => { :media => :quicktime_movie, :type => :video },
    "\x03\xD9\x84\x00mdat" => { :media => :quicktime_movie, :type => :video },
    "\x00\x00\x00\x14fty3gp5" => { :media => :mpeg4_video, :type => :video },
    "\x00\x00\x00\x14ftymp42" => { :media => :mpeg4_video_quicktime, :type => :video },
    "\x00\x00\x00\x1Cftypmp42" => { :media => :mpeg4_video_quicktime, :type => :video },
    "\x00\x00\x00\x00G@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x00\x6CG@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x08\xE3G@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x08\xE2G@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x08\xE1G@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x0B\xA9G@" => { :media => :avchd_mts, :type => :video },
    "\x00\x00\x0B\xA8G@" => { :media => :avchd_mts, :type => :video }
  }

  MagicNumberTypeMaxLength = 64  # Longest key


  # Detect the data type by checking various "magic number" conventions
  # for the introductory bytes of a data stream
  #
  # Return the "magic number" as a symbol:
  #  - :bitmap = Bitmap image file, typical extension ".bmp"
  #  - :gzip = Unix GZIP compressed data, typical extension ".gz"
  #  - :postscript = Postscript pages, typical extension ".ps"
  #
  # Return nil if there's no match for any known magic number.
  #
  # Examples:
  #   "BM".magic_number_type => :bitmap
  #   "GIF8".magic_numer_type => :gif
  #   "\xa6\x00".magic_number_type => :pgp_encrypted_data
  #
  # TODO change from hash implementation to binary tree
  #
  def magic_number_type
    String::MagicNumberTypeHash.each_pair do |byte_string,type_symbol|
      return type_symbol if byte_string==self.byteslice(0,byte_string.length)
    end
    return nil
  end

  protected

end

class IO

  # Detect the data type by checking various "magic number" conventions
  # for the introductory bytes of a data stream
  #
  # Return the "magic number" as a symbol:
  #  - :bitmap = Bitmap image file, typical extension ".bmp"
  #  - :gzip = Unix GZIP compressed data, typical extension ".gz"
  #  - :postscript = Postscript pages, typical extension ".ps"
  #
  # Return nil if there's no match for any known magic number.
  #
  # Example:
  #   IO.f = File.open("test.ps","rb")
  #   put f.magic_number(s)
  #   => :postscript
  #
  # See:
  #  - IO::MagicNumberTypeHash
  #  - File.magic_number_type
  #
  # TODO change from hash implementation to binary tree

  def magic_number_type(bytes=self.read(String::MagicNumberTypeMaxLength))
    #bytes.each_byte do |byte|
      #STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
    #end
    return nil if bytes == nil
    String::MagicNumberTypeHash.each_pair do |byte_string,metadata|
      return metadata if byte_string==bytes[0,byte_string.length]
    end
    return nil
  end

end


class File

  # Detect the file's data type by opening the file then
  # using IO#magic_number_type to read the first bits.
  #
  # Return a magic number type symbol, e.g. :bitmap, :jpg, etc.
  #
  # Example:
  #   puts File.magic_number_type("test.ps") => :postscript
  #
  # See
  #   - IO#MagicNumberTypeHash
  #   - IO#magic_number_type
  #
  def self.magic_number_type(file_name)
    f = File.open(file_name,"rb")
    type = f.magic_number_type
    f.close
    return type
  end

end



class MediaMetadata
  class << self
    
    # fetch the creation time of a .mts file.
    # Based on https://github.com/MichihiroOkada/mtsinfo
    # Reference: http://hirntier.blogspot.com/2009/08/avchd-timecodes-revealed.html
    # Reference: http://www.sno.phy.queensu.ca/~phil/exiftool/TagNames/H264.html
    def get_mts_creation_time(io)

	# Scan the file looking for "MDPM"
        read_size = 0
        while(data = io.read(500)) 
          mdpm_index = /MDPM/ =~ data
          if(mdpm_index)
            read_size = read_size + mdpm_index
            io.seek(read_size, IO::SEEK_SET)
            break
          else
            io.seek(-4, IO::SEEK_CUR)
            read_size = read_size + 500 - 4
          end
        end
      
        mdpm_data = io.read(20)
        datetag_index_top = mdpm_data.index("\x18")
        datetime = sprintf("%02x%02x-%02x-%02xT%02x:%02x:%02x",
                mdpm_data[datetag_index_top+2].unpack("C*").join,
                mdpm_data[datetag_index_top+3].unpack("C*").join,
                mdpm_data[datetag_index_top+4].unpack("C*").join,
                mdpm_data[datetag_index_top+6].unpack("C*").join,
                mdpm_data[datetag_index_top+7].unpack("C*").join,
                mdpm_data[datetag_index_top+8].unpack("C*").join,
                mdpm_data[datetag_index_top+9].unpack("C*").join)
    
        if(datetime)
          #puts "[MTSPARSE] datetime = " + datetime
          return DateTime.parse(datetime)
        else
          return 0
        end
    end  
    
    
    # Fetch the creation time of a .mov file
    # Based on https://github.com/verm666/mp4info
    # Reference: https://developer.apple.com/library/mac/documentation/QuickTime/QTFF/QTFFChap2/qtff2.html#//apple_ref/doc/uid/TP40000939-CH204-56313
    def get_mov_creation_time(io)
      
      offset = 0
      atom_size = 0
      
      while offset < io.size
        atom_size = io.read(4).unpack("N").first
        atom_type = io.read(4)
        #puts "Atom type: #{atom_type}"
      
        if atom_type == "moov"
          io.seek(offset)
          moov_size = io.read(4).unpack("N").first
          moov_type = io.read(4)
        
          #puts "moov_size: #{moov_size}, moov_type: #{moov_type}"
        
          moov_size = offset + moov_size
        
          offset += 8
          while offset < moov_size do
            size = io.read(4).unpack("N").first
            type = io.read(4)
        
            if type == "mvhd"
              offset += 8 #Skip size & Type
              io.seek(offset)
            
              version = io.read(1).unpack("C").first # C - 8-bit
              flags = io.read(3)
            
              if version.to_i == 0
                ctime = io.read(4).unpack("N").first
                mtime = io.read(4).unpack("N").first
                scale = io.read(4).unpack("N").first
                duration = io.read(4).unpack("N").first
              elsif version.to_i == 1
                ctime = io.read(8).unpack("Q").first
                mtime = io.read(8).unpack("Q").first
                scale = io.read(4).unpack("N").first
                duration = io.read(8).unpack("Q").first
              end 
    	      #puts ctime
    
    	      return 0 if ctime == 0
            
	      # ctime & mtime are in seconds since midnight, January 1, 1904
	      # UNIX time is seconds since Thursday, 1 January 1970
              epoch_adjuster = 2082844800
              #puts Time.at(ctime - epoch_adjuster).to_datetime
              #puts Time.at(mtime - epoch_adjuster).to_datetime
            
              return Time.at(ctime - epoch_adjuster).to_datetime
            end
            
            offset += size
            io.seek(offset)
          end
        end
      
        offset += atom_size
        io.seek(offset)
      end
    end
    
    # Extract jpeg creation time
    # Reference: http://www.codeproject.com/KB/graphics/ExifLibrary/jpeg_format.png
    def get_jpeg_creation_time(io)
       @MARKERS = {
            "\xFF\xD8" => 'SOI',
            "\xFF\xc0" => 'SOF0',
            "\xFF\xc1" => 'SOF1',
            "\xFF\xc2" => 'SOF2',
            "\xFF\xc3" => 'SOF3',
    
            "\xFF\xc5" => 'SOF5',
            "\xFF\xc6" => 'SOF6',
            "\xFF\xc7" => 'SOF7',
    
            "\xFF\xc8" => 'JPG',
            "\xFF\xc9" => 'SOF9',
            "\xFF\xca" => 'SOF10',
            "\xFF\xcb" => 'SOF11',
    
            "\xFF\xcd" => 'SOF13',
            "\xFF\xce" => 'SOF14',
            "\xFF\xcf" => 'SOF15',
    
            "\xFF\xc4" => 'DHT',
   
            "\xFF\xcc" => 'DAC',
   
            "\xFF\xd0" => 'RST0',
            "\xFF\xd1" => 'RST1',
            "\xFF\xd2" => 'RST2',
            "\xFF\xd3" => 'RST3',
            "\xFF\xd4" => 'RST4',
            "\xFF\xd5" => 'RST5',
            "\xFF\xd6" => 'RST6',
            "\xFF\xd7" => 'RST7',
    
            #"\xFF\xd8" => 'SOI',
            "\xFF\xd9" => 'EOI',
            "\xFF\xda" => 'SOS',
            "\xFF\xdb" => 'DQT',
            "\xFF\xdc" => 'DNL',
            "\xFF\xdd" => 'DRI',
            "\xFF\xde" => 'DHP',
            "\xFF\xdf" => 'EXP',
    
            "\xFF\xe0" => 'APP0',
            "\xFF\xe1" => 'APP1',
            "\xFF\xe2" => 'APP2',
            "\xFF\xe3" => 'APP3',
            "\xFF\xe4" => 'APP4',
            "\xFF\xe5" => 'APP5',
            "\xFF\xe6" => 'APP6',
            "\xFF\xe7" => 'APP7',
            "\xFF\xe8" => 'APP8',
            "\xFF\xe9" => 'APP9',
            "\xFF\xea" => 'APP10',
            "\xFF\xeb" => 'APP11',
            "\xFF\xec" => 'APP12',
            "\xFF\xed" => 'APP13',
            "\xFF\xee" => 'APP14',
            "\xFF\xef" => 'APP15',
            "\xFF\xf0" => 'JPG0',
            "\xFF\xfd" => 'JPG13',
            "\xFF\xfe" => 'COM',
            "\xFF\x01" => 'TEM'
        }

    	content = io.read # read enough to load just the header
    	position = 2
        mark = content[position-2...position]
        if @MARKERS[mark] != "SOI"
          #puts "Not a jpeg file"
          return 0
        end
    
    	markers = Array.new()
        while true
    	  position += 2
          type = content[position-2...position]

    	  #puts type
          #type.each_byte do |byte|
            #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
          #end

          # finished reading all the metadata
          if @MARKERS[type] == 'SOS'
            #puts "Reached the end"
            return 0
          end
    
    	  position += 2
          size = content[position-2...position]
          data_size = size.unpack('n')[0]-2
    
    	  #puts "Data Size: #{data_size}"
    
    	  position += data_size
          data = content[position-data_size...position]
    
          if @MARKERS[type] == 'APP1'
            #puts "Reached the EXIF"
    
            #data[0...6].each_byte do |byte|
               #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end

	    # Make sure we have an EXIF\0\0
	    if data[0...6] != "Exif\0\0"
	      # This jpg has no EXIF section
	      return 0
	    end

    	    # Skip the {'E', 'X', 'I', 'F', '\0', '\0'}
    	    data = data[6...data_size] #TODO: No need to copy
    
            # Figure out the exif endianess
            little_endian = (data[0] == ?I)
            format2bytes, format4bytes = little_endian ? %w[v V] : %w[n N]
    
            #data.each_byte do |byte|
                #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end
    
            tiff_offset = 0
    
    	    # skip byte order
    	    tiff_offset += 2
    
    	    # skip TIFF ID
    	    tiff_offset += 2
    
    	    # Get the offset to IFD 0
            buf = data[tiff_offset...(tiff_offset+4)]
            tiff_offset = buf.unpack(format4bytes)[0]
            #puts "Offset of IFD 0 from  TIFF header : #{tiff_offset}"
    
            # Number of Interoperability (tags)
            buf = data[tiff_offset...(tiff_offset+2)]

            #buf.each_byte do |byte|
              #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end
    
            tags = buf.unpack(format2bytes)[0]
    	    #puts "# of tags: #{tags}"
    
    	    # Skip the tag count field
    	    tiff_offset += 2
    
            date_time_tag = 0x0132
            date_time_original_tag = 0x9003
	    exif_offset_tag = 0x8769
            tags.times do
              buf = data[tiff_offset...(tiff_offset+12)] #Each field is 12 bytes
              tag = buf.unpack(format2bytes)[0]
              #puts "Found tag: #{tag} #{tag.to_s(16)}"
              #buf.each_byte do |byte|
                #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
              #end

              # Looks like we found an EXIF offset. Look in that offset for our date/time.
	      if tag == exif_offset_tag
                exif_offset = buf[-4,4].unpack(format4bytes)[0]
	        #puts "Gonna look in the exif location #{exif_offset.to_s(16)}"

                # Number of Interoperability (tags)
                buf = data[exif_offset...(exif_offset+2)]
                #buf.each_byte do |byte|
                  #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
                #end
    
                tags = buf.unpack(format2bytes)[0]
    	        #puts "# of tags: #{tags}"
    
    	        # Skip the tag count field
    	        exif_offset += 2

                tags.times do
                  buf = data[exif_offset...(exif_offset+12)] #Each field is 12 bytes
                  exif_offset+=12
                  tag = buf.unpack(format2bytes)[0]
                  #puts "Found tag: #{tag} #{tag.to_s(16)}"
                  #buf.each_byte do |byte|
                    #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
                  #end
                  if (tag == date_time_tag) || (tag == date_time_original_tag)
                    #puts "Found the creation date/time tag"
                    offset = buf[-4,4].unpack(format4bytes)[0]
                    buf = data[offset...(offset+19)] # skip last null char
                    #buf.each_byte do |byte|
                      #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
                    #end
                        #puts buf.nil?
                    #buf.scan(/\d+/) { |d| puts d.nil? }
                    if buf =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/
    		      #puts "HMM: ALL ZEROES"
                      return 0 if ($1.to_i | $2.to_i | $3.to_i | $4.to_i | $5.to_i | $6.to_i) == 0
                    end
                    return Time.mktime(*buf.scan(/\d+/)).to_datetime
                  end
		end
	      end

              if tag == date_time_tag
                #puts "Found the creation date/time tag"
                offset = buf[-4,4].unpack(format4bytes)[0]
                buf = data[offset...(offset+19)] # skip last null char
                #buf.each_byte do |byte|
                  #puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
                #end
                #puts buf.nil?
                #buf.scan(/\d+/) { |d| puts d.nil? }
                if buf =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/
    		  #puts "HMM: ALL ZEROES"
                  return 0 if ($1.to_i | $2.to_i | $3.to_i | $4.to_i | $5.to_i | $6.to_i) == 0
                end
                return Time.mktime(*buf.scan(/\d+/)).to_datetime
              end
              tiff_offset+=12
            end
          end
        end
    end

    # Extract Tiff/CR2 creation time
    # Reference: https://gist.github.com/paulschreiber/431893
    def get_tiff_creation_time(io)  # DateTime of Exif: Tag=306 (132.H)
        img_top = io.read(1024)
        if not (img_top[0, 4] == "MM\x00\x2a" or img_top[0, 4] == "II\x2a\x00")
          raise 'malformed TIFF'
        end
        
        io.seek(0, 0)
    
        # define Singleton-method definition to IO (byte, offset)
        def io.read_o(length = 1, offset = nil)
          self.seek(offset, 0) if offset
          ret = self.read(length)
          raise "cannot read!!" unless ret
          ret
        end
    
        # 'v' little-endian   'n' default to big-endian
        endian = if (io.read_o(4) =~ /II\x2a\x00/o) then 'v' else 'n' end
    
        packspec = [
          nil,           # nothing (shouldn't happen)
          'C',           # BYTE (8-bit unsigned integer)
          nil,           # ASCII
          endian,        # SHORT (16-bit unsigned integer)
          endian.upcase, # LONG (32-bit unsigned integer)
          nil,           # RATIONAL
          'c',           # SBYTE (8-bit signed integer)
          nil,           # UNDEFINED
          endian,        # SSHORT (16-bit unsigned integer)
          endian.upcase, # SLONG (32-bit unsigned integer)
        ]
    
        offset = io.read_o(4).unpack(endian.upcase)[0] # Get offset to IFD
    
        ifd = io.read_o(2, offset)
        num_dirent = ifd.unpack(endian)[0]                   # Make it useful
        offset += 2
        num_dirent = offset + (num_dirent * 12);             # Calc. maximum offset of IFD
    
        datetime = ifd = 0
        while(true)
          ifd = io.read_o(12, offset)                 # Get first directory entry
          break if (ifd.nil? || (offset > num_dirent))
          offset += 12
          tag = ifd.unpack(endian)[0]                       # ...and decode its tag
          type = ifd[2, 2].unpack(endian)[0]                # ...and the data type
    
          #puts "#{type} : #{tag}"
    
          # Check the type for sanity.
          #next if (type > packspec.size + 0) || (packspec[type].nil?)
    
          if tag == 0x0132  # Decode the value
            img_offset = ifd[8, 4].unpack(endian.upcase)[0]
            datetime = img_top[img_offset, 20].unpack('CCCCCCCCCCCCCCCCCCC').map { |i| i.chr }.join
            if datetime =~ /^(\d{4}):(\d\d):(\d\d) (\d\d):(\d\d):(\d\d)$/
              begin
                datetime = Time.local($1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i, $6.to_i).to_datetime
              rescue => ex
                datetime = 0
              end
            else
              datetime = 0
            end
          end
        end
    
        return datetime
    end
    
    def get_png_creation_time(io)  # DateTime of Exif: Tag=306 (132.H)
        hdr = io.read(8)
        raise "Not a PNG File" if hdr[0,4]!= "\211PNG"
        raise "file not in binary mode" if hdr[4,4]!="\r\n\032\n"

        # Scan all the chunks looking for tEXt, iTXt or zTXt
        loop do
          lenword = io.read(4)
          length = lenword.unpack('N')[0]
          chunk_type = io.read(4)
          chunk_data = length>0 ? io.read(length) : ""
          chunk_crc = io.read(4)
    
          if chunk_type == 'tEXt'
            chunk_data = chunk_data.unpack('Z*a*')
    	    p chunk_data[1]
            #chunk_data.each_byte do |byte|
              #STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end
            if chunk_data[0] == 'Creation Time'
              #pp Date.parse(chunk_data[1])
            end
          elsif chunk_type == 'zTXt'
            chunk_data = chunk_data.unpack('Z*Ca*')
            chunk_data[2] = Zlib::Inflate.inflate(chunk_data[2])
            p chunk_data[1]
            #chunk_data.each_byte do |byte|
              #STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end
    	    if chunk_data[0] == 'Creation Time'
    	      #pp Date.parse(chunk_data[1])
    	    end
          elsif chunk_type == 'iTXt'
            #@xml = Nokogiri::XML.parse(@xmp_data)
            chunk_data = chunk_data.unpack('Z*a*')
            pp chunk_data
            #chunk_data.each_byte do |byte|
              #STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            #end
          elsif chunk_type == 'tIME'
            chunk_data.each_byte do |byte|
              STDOUT.puts [byte.chr, byte.to_s, ("0x%02X" % byte)].join("\t")
            end
            pp chunk_data.unpack('S>CCCCC')
            datetime = chunk_data.unpack('S>CCCCC')
            modification_datetime = Time.local(datetime[0], datetime[1], datetime[2], datetime[3],datetime[4], datetime[5], datetime[6]).to_datetime
    	    #return modification_datetime
          end
          puts "Chunk: #{chunk_type} -> Length: #{length}"

          break if length<0 || !(('A'..'z')===chunk_type[0,1]) || chunk_type.nil? || chunk_type == 'IEND'
        end
      #end
    end


    def parse filename

      raise "File #{filename} not found" if !File.exists?(filename)


      File.open(filename, "rb") do |f|

        metadata = f.magic_number_type

	f.rewind

        # We found a match for file magic, now check the media creation time.
        if metadata

          created_on = 0

	  case metadata[:media]
	  when :quicktime_movie, :iso_base_media
            created_on = MediaMetadata.get_mov_creation_time(f)
            #puts "Movie created_on : #{created_on}"
          when :jpeg
            created_on = MediaMetadata.get_jpeg_creation_time(f)
            #puts "JPEG created_on : #{created_on}"
            #pp created_on
          when :tiff
            created_on = MediaMetadata.get_tiff_creation_time(f)
            #puts "TIFF created_on : #{created_on}"
          when :avchd_mts
            created_on = MediaMetadata.get_mts_creation_time(f)
            #puts "MTS created_on : #{created_on}"
          #when :png
            #created_on = MediaMetadata.get_png_creation_time(f)
            #puts "PNG created_on : #{created_on}"
          end 

          # either we have a creation time, or creation time is nil
	  metadata[:created_on] = created_on
	else
	  # unknown media. Return all unknown
	  metadata = { :media => :unknown, :type => :unknown, :created_on => 0 }
	end

        #pp metadata

        f.close
    
        return metadata
      end
    end
  end
end

if __FILE__ == $0
  puts MediaMetadata.parse(ARGV[0])
end

