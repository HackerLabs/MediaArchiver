#!/usr/bin/env ruby

require 'find'
require "fileutils"
require 'optparse'
require 'pp'
require 'zlib'
require './lib/Signatures'
require './lib/DirIterator'
require './lib/MediaType'
require 'pathname'

$stdout.sync = true

class Archiver
   OTHER_DIR = "MANUAL-CHECK-NEEDED"
   SEPARATOR = File::SEPARATOR

   # dup modes
   IGNORE_DUPS = 0
   SKIP_DUPS   = 1
   MARK_DUPS   = 2
   NOT_A_DUP   = -1

   def initialize source_path, dest_dir, threshold, cmd_options
      @source_path = source_path
      @dest_dir = dest_dir
      @threshold = threshold

      @cmd_options = cmd_options.clone
      @cp_cmd_options = cmd_options.clone
      @cp_cmd_options[:preserve] = true

      #Fetch the media metadata
      @metadata = get_metadata

      #verbose "Threshold: #{@threshold}"
      #verbose "Processing:  #{@source_path}"
   end

   def ext
      File.extname(@source_path.downcase)
   end

   def is_video?
      #verbose "VIDEO: #{ext.upcase}"
      return @metadata[:type] == :video
   end

   def is_image?
      #verbose "IMAGE: #{ext.upcase}"
      return @metadata[:type] == :image
   end

   def get_metadata(file = nil)
      file = @source_path if file == nil
      metadata = MediaMetadata.parse(file);
      #verbose "Media: #{file} metadata: #{metadata}"
      return metadata
   end

   def original_name
      File.basename @source_path
   end

   def original_name_without_ext
      original_name.chomp(File.extname(original_name) )
   end

   def path_from_timestamp_without_ext(timestamp = nil)
      file_timestamp = (timestamp != nil)?timestamp:@metadata[:created_on]

      if file_timestamp != 0
         if is_video?
            return "#{@dest_dir}#{SEPARATOR}#{file_timestamp.year}#{SEPARATOR}#{file_timestamp.strftime("%b")}#{SEPARATOR}#{file_timestamp.strftime("%d-%a")}#{SEPARATOR}VIDEO#{SEPARATOR}#{file_timestamp.strftime("%I-%M-%S-%p")}"
         elsif is_image?
            return "#{@dest_dir}#{SEPARATOR}#{file_timestamp.year}#{SEPARATOR}#{file_timestamp.strftime("%b")}#{SEPARATOR}#{file_timestamp.strftime("%d-%a")}#{SEPARATOR}IMG#{SEPARATOR}#{file_timestamp.year}-#{file_timestamp.strftime("%b-%d-%a-%I-%M-%S-%p")}"
         else
            return "#{@dest_dir}#{SEPARATOR}#{OTHER_DIR}#{SEPARATOR}#{original_name_without_ext}"
         end
      else
         return "#{@dest_dir}#{SEPARATOR}#{OTHER_DIR}#{SEPARATOR}#{@source_path.gsub(':', '')}"
      end
   end

   def path_from_timestamp(append = "", timestamp = nil)
      return "#{path_from_timestamp_without_ext(timestamp)}#{append}#{ext}"
   end

   def file_with_same_name_exists?(path)
      exists = File.exists? path
      #verbose "File #{path} exists = #{exists}"
      return exists
   end

   # Returns (is_duplicate?, path)
   def get_path(mode, signature, append = "")
      path = path_from_timestamp(append)
      count = 1
      while(file_with_same_name_exists?(path))
         #dest_sig = Digest::MD5.file(path)
         #dest_sig = Signatures.crc(path)
         dest_sig = Signatures.crc(path)
         if (mode != IGNORE_DUPS) && (signature == dest_sig)
            #puts "SKIPPING : #{@source_path} & #{path} have same signature: #{dest_sig}."
            #puts " "
            return true, path
         else
            #verbose "File #{path} exists, incrementing"
            path = path_from_timestamp("#{append}-COPY_#{count}")
            count += 1
         end
      end

      return false, path
   end

   def copy(mode)

      if !is_video? && !is_image?
         verbose "IGNORING #{@source_path} : UNKNOWN MEDIA TYPE: #{@metadata}"
         return
      end

      signature = Signatures.crc(@source_path)
      duplicate, dest_path = get_path(mode, signature)

      # Figure out the path to copy to.
      if mode == IGNORE_DUPS
         verbose "COPYING DUPLICATE TO: #{dest_path}"
      else
         if duplicate
            if mode == SKIP_DUPS
               # Skipping it
               verbose "SKIPPING : FOUND DUPLICATE: #{dest_path}"
               return
            elsif mode == MARK_DUPS
               #verbose "WILL MARK AS DUP"
               # Need to find a suitable name for the dup
               append = "-DUPLICATE_OF-#{File.basename(dest_path)}"

               #verbose "Appending: #{append}"
               # Just get the new file name, ignoring dups
               # I already know there is a dupe. I just want a new path created
               # with my append string.
               duplicate, dest_path = get_path(IGNORE_DUPS, signature, append)
               verbose "COPYING DUPLICATE TO: #{dest_path}"
            end
         else
            verbose "COPYING TO: #{dest_path}"
         end
      end

      FileUtils.mkdir_p File.dirname(dest_path), @cmd_options
      FileUtils.cp @source_path, dest_path, @cp_cmd_options
   end

   def check
      if !is_video? && !is_image?
         verbose "IGNORING #{@source_path} : UNKNOWN FORMAT: #{ext}"
         return
      end

      dest_path = path_from_timestamp

      if @metadata[:created_on]
         pattern = "#{@timestamp.year}#{SEPARATOR}#{@timestamp.strftime("%b")}#{SEPARATOR}#{@timestamp.strftime("%d-%a")}"

         if @source_path.include? pattern
            #puts "MATCH: #{@source_path} -> #{dest_path}"
         else
            #verbose "MISMATCH: #{@source_path} -> #{dest_path}"
            FileUtils.mkdir_p File.dirname(dest_path), @cmd_options
            FileUtils.mv  @source_path, dest_path, @cp_cmd_options
         end
      else
         #verbose "MISMATCH: #{@source_path} -> #{dest_path}"
         FileUtils.mkdir_p File.dirname(dest_path), :verbose => true
         FileUtils.mv @source_path, dest_path, :verbose => true
      end
   end
end

class MediaArchiver

   def archive options

      #Load the iterator
      iter = nil
      if File.file?(options[:state_file])
         begin
            verbose "Will restart previous run. Loading state from #{options[:state_file]}"
            File.open(options[:state_file], 'rb') { |state| iter = Marshal.load(state) }

            # delete the state file if we are able to load it.
            File.delete(options[:state_file]);
         rescue => exception
            puts exception.backtrace
            verbose "Invalid state file #{options[:state_file]}. Starting over from beginning"
            f = DirIterator.new options[:input_dir]
            iter = f.iterator
            raise exception
         end
      else
         f = DirIterator.new options[:input_dir]
         iter = f.iterator
         verbose "Fresh start ..."
      end

      #f.add_extensions ".jpg", ".jpeg"

      begin
         while nxt = iter.next
            verbose "\n#{nxt} : "
            if options[:verify]
               Archiver.new(nxt.to_s, options[:output_dir], options[:threshold], options[:cmd_options]).check
            else
               Archiver.new(nxt.to_s, options[:output_dir], options[:threshold], options[:cmd_options]).copy(options[:mode])
            end
         end
      rescue => exception
         puts exception.backtrace
         verbose "Saving state to #{options[:state_file]} ..."
         # rewind the iterator so we can restart where we failed
         iter.prev
         File.open(options[:state_file], 'wb') { |p| Marshal.dump(iter, p) }
         raise exception
      end
   end
end

$options = {}
option_parser = OptionParser.new do |o|
   o.on('-d [0/1/2]', "Enable duplicate detection. The mode signifies the action to take",
        "0 = No duplicate detection. Copy all files",
        "1 = Detect and skip all duplicates",
        "2 = Detect and mark duplicates",
        "", " ") { |b|
           if b == nil
              b = 0
           end

           b = b.to_i

           if ((b < 0) || (b > 2))
              puts "ERROR: unknown duplicate detection mode: #{b}"
              puts option_parser
              exit
           end

           $options[:mode] = b
        }
        o.on('-i INPUT_DIR') { |path| $options[:input_dir] = path }
        o.on('-o OUTPUT_DIR') { |path| $options[:output_dir] = path }
        o.on('-h', "Help") { puts o; exit }
        o.on('-v', "Verbose") { |b| $options[:verbose] = b }
        o.on('-c', "Check") { |b| $options[:verify] = b }
        o.on('-n', "Dry Run") { |b| $options[:noop] = b }
end


begin
   option_parser.parse!
rescue OptionParser::ParseError
   puts option_parser
   exit
end

unless $options[:input_dir] && $options[:output_dir]
   puts "ERROR: Both INPUT & OUTPUT directory is needed"
   puts option_parser
   exit;
end

def verbose(str)
   if $options[:verbose]
      #puts "#{str}"
      print "#{str}"
   end
end

#remove any trailing /
$options[:input_dir] = $options[:input_dir].sub(/(#{File::SEPARATOR})+$/,'')
$options[:output_dir] = $options[:output_dir].sub(/(#{File::SEPARATOR})+$/,'')

#On windows convert ALT_SEPARATOR to SEPARATOR
$options[:input_dir] = $options[:input_dir].gsub(/[\\]/,"/")
$options[:output_dir] = $options[:output_dir].gsub(/[\\]/,"/")


# If no dup detection is specified, assume MARK_DUPS
if !$options[:mode]
   $options[:mode] = Archiver::MARK_DUPS
end

if $options[:noop]
   $options[:verbose] = true
end

#$options[:cmd_options] = { :verbose => $options[:verbose], :noop => $options[:noop] }
$options[:cmd_options] = { :noop => $options[:noop] }

# State file is constructed from input and output path.
state_file = $options[:input_dir].gsub(/[\\\/-:]/,'_') + '--to--' + $options[:output_dir].gsub(/[\\\/-:]/,'_') + ".state"
$options[:state_file] = state_file

# Alllllllllrighty then...
MediaArchiver.new.archive $options
