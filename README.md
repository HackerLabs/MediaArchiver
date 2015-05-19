# MediaArchiver
Extremely fast Photo and Video organizer. Photos and Videos are organized/archived based on their creation time extracted from metadata embedded within the media.

## Features
- Supports .jpg, .tiff, .cr2 (Canon RAW), .mov, .mts, .mp4
- Extremely fast as it is written in pure Ruby with no additional gems/libraries/binaries needed. 
- Photos and Videos are identified based on file content (file magic) and not from file extension. 
- Parses and extracts the creation/modification time from exif/metadata embedded within the photo/video. No external exif parsers (like exiftool) is required. 
- Duplicate detection based on checksum (CRC/Adler32). Duplicate media can be skipped or marked "DUPLICATE" and archived. 
 
## Usage

run `MediaArchiver.rb` from the command line

```bash
MediaArchiver.rb -d [0/1/2]    # Enable duplicate detection. 
                            # The mode signifies the action to take
                            # 0 = No duplicate detection. Copy all files
                            # 1 = Detect and skip all duplicates
                            # 2 = Detect and mark duplicates
              -i INPUT_DIR  # The input folder where original media is found
              -o OUTPUT_DIR # The output folder where media is to be archived
              -v            # Verbose output
              -c            # Check the INPUT_DIR for proper archival of media, 
                            # move them to OUTPUT_DIR if improperly archived
              -n            # Dry Run. Does not actually move/copy files, 
                            # but lets you see what would happen.
```


