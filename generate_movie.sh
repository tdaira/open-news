#!/bin/bash

# Clean output directory
rm -rf output
mkdir -p output

# Specify audio file path
audio_file="audio.wav"
lipsync_data_file="output/lipsync_data.tsv"
rhubarb -o "$lipsync_data_file" -r phonetic "$audio_file"

# Initialize variables
count=0
current_frame_time=0
frame_duration=0.033333333

# Load lipsync data into arrays
timestamps=()
mouth_shapes=()
while IFS=$'\t' read -r time shape; do
  timestamps+=("$time")
  mouth_shapes+=("$shape")
done < "$lipsync_data_file"

# Get the length of mouth shape data
data_length=${#timestamps[@]}
current_data_index=0

next_timestamp=${timestamps[1]}
mouth_shape=${mouth_shapes[0]}

# Get audio duration
total_duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file")

# Generate frames sequentially
while true; do
  # Calculate current frame time
  current_frame_time=$(echo "$count * $frame_duration" | bc)

  # Move to next data point when current frame time exceeds next timestamp
  while (( $(echo "$current_frame_time >= $next_timestamp" | bc -l) )) && [ $current_data_index -lt $((data_length-1)) ]; do
    current_data_index=$((current_data_index+1))
    if [ $current_data_index -lt $((data_length-1)) ]; then
      next_timestamp=${timestamps[$current_data_index+1]}
    else
      next_timestamp=$total_duration
    fi
    mouth_shape=${mouth_shapes[$current_data_index]}
  done

  # Generate frame
  frame_number=$(printf "%04d" "$count")
  # Blink eyes every 5 seconds (2 frames)
  if [ $((count % 150)) -eq 0 -o $((count % 150)) -eq 1 ]; then
    eye_shape="close"
  else
    eye_shape="open"
  fi
  eye_image="images/eye/${eye_shape}.png"
  mouth_image="images/mouth/${mouth_shape}.png"
  output_frame="output/frame_${frame_number}.png"
  magick images/face.png \
    \( "${mouth_image}" -geometry 70%x70%+7-87 -gravity center \) -composite \
    \( "${eye_image}" -geometry +4-219 -gravity center \) -composite \
    "${output_frame}"

  count=$((count+1))

  # Exit when exceeding audio duration
  if (( $(echo "$current_frame_time > $total_duration" | bc -l) )); then
    break
  fi
done

# Generate final video
ffmpeg -y -framerate 30 -i output/frame_%04d.png -i "$audio_file" -c:v libx264 -c:a aac -pix_fmt yuv420p output/video.mp4
