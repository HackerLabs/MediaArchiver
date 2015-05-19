# MediaArchiver
Extremely fast Photo and Video organizer. Photos and Videos are organized/archived based on their creation time extracted from metadata embedded within the media.

## Features
- Supports .jpg, .tiff, .cr2 (Canon RAW), .mov, .mts, .mp4
- Extremely fast as it is written in pure Ruby with no additional gems/libraries/binaries needed. 
- Photos and Videos are identified based on file content (file magic) and not from file extension. 
- Parses and extracts the creation/modification time from exif/metadata embedded within the photo/video. No external exif parsers (like exiftool) is required. 
- Duplicate detection based on checksum (CRC/Adler32). Duplicate media can be skipped or marked "DUPLICATE" and archived. 
 
