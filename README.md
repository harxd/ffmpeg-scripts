# Containerized FFmpeg Transcode Scripts

Minimal, zero-dependency bash scripts to orchestrate and monitor containerized ffmpeg instances locally (via Podman or Docker).

### Installation / First Run
```bash
git pull https://github.com/harxd/ffmpeg-scripts.git
chmod +x transcode.sh status.sh
./transcode.sh
```
*Running `./transcode.sh` for the very first time will auto-generate the customizable `config.yaml`.*

### Update
To pull the latest scripts from the repository **without** risking your custom configurations:
```bash
git pull
```
## Scripts

- **`transcode.sh`**: 
  
  ```bash
  ./transcode.sh /path/to/source_video.mkv
  ```

- **`status.sh`**: Progress tracker.  
Live-updating CLI dashboard calculating ETA, speed, frame targets, and bitrate.
  
  ```bash
  ./status.sh
  ```
  Example:
  ```
  [user@alma ~]$ ./status.sh 
  File:     Pass --name
  Progress: [#######-----------------------] 26.5%
  Frame:    6121
  FPS:      6.8
  Bitrate:  4200.4kbits/s
  Position: 00:03:24
  Elapsed:  00:15:03
  ETA:      00:41:43
  ```

## Configuration
**`config.yaml`**

```yaml
# FFmpeg Transcode Configuration

# Global
# Name of the podman/docker container used for transcoding
container_name: "ffmpeg"
# Engine to run the container. Options: "podman", "docker"
container_engine: "podman"
# Where the transcoded files will be saved.
# Leave empty "" to save directly in the source video's directory.
# (Safety feature: if 'output_suffix' is also empty, the video codec name will be automatically appended to prevent overwriting the original file).
output_dir: ""
# Set to "true" if SELinux is running on your system to append ":z" to volume mounts
selinux: "true"

# Output Formatting
# Appended to the original filename (e.g. video [RF23-2].mkv). Leave empty "" to auto-append the transcoded video codec name.
output_suffix: ""
# Options: mkv, mp4, webm
output_container: "mkv"

# Video Encoding Settings (SVT-AV1)
# Options: libsvtav1 (AV1), libx264 (H264), libx265 (HEVC)
video_codec: "libsvtav1"
# Preset speed. SVT-AV1: 0-13 (0 is slowest). x264/x265: ultrafast to veryslow
video_preset: "2"
# Constant Rate Factor. Lower = better quality/larger file. Typical: 18-28.
video_crf: "23"
# Visual tuning. SVT-AV1 options: 0 (Visual Quality), 1 (PSNR), 2 (SSIM), 3 (Subjective)
video_tune: "0"
# Options: yuv420p10le (10-bit, recommended) or yuv420p (8-bit)
video_pix_fmt: "yuv420p10le"
# Options: cfr (Constant Framerate) or vfr (Variable Framerate)
video_fps_mode: "cfr"

# Audio Encoding Settings
# Comma-separated list of audio codecs to copy directly without re-encoding
audio_passthrough_codecs: "aac"
# Used if source is not in the passthrough list. Options: libopus, libmp3lame, ac3, flac, aac
audio_fallback_codec: "libopus"
# Fallback audio bitrate. Options: 96k, 128k, 192k, 256k, 320k
audio_fallback_bitrate: "128k"
```