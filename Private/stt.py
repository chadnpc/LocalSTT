import os
import time
import wave
import socket
import argparse
import threading
import pyaudio
import numpy as np
import json

# --- Argument Parsing ---
parser = argparse.ArgumentParser(description='Audio Recording with Socket Output')
parser.add_argument('--host', type=str, default='127.0.0.1', help='Host for the socket connection')
parser.add_argument('--port', type=int, default=65432, help='Port for the socket connection')
parser.add_argument('--amplify-rate', type=float, default=1.1, help='Amplification rate for audio')
parser.add_argument('--outfile', type=str, default=time.strftime("%Y%m%d-%H%M%S") + "_output.wav", help='Output file for the recorded audio')
parser.add_argument('--duration-in-minutes', type=float, default=3, help='Duration of the recording in minutes')
parser.add_argument('--working-directory', type=str, default=os.getcwd(), help='Working directory for the script')
args = parser.parse_args()

# --- Globals ---
client_socket = None
stop_event = threading.Event()

# Audio recording settings
FORMAT = pyaudio.paInt16
CHANNELS = 1
RATE = 44100
CHUNK = 1024
DURATION = args.duration_in_minutes
frames = []
percent = 0
elapsed_time = 0

audio = pyaudio.PyAudio()
stream = None

def select_best_audio_device(devices):
    """
    Selects the best audio input device from an array of available devices (array of List[dict])
    Based on the number of input channels it returns the index of the best device.
    """
    try:
        if not devices:
          raise ValueError("No audio input devices found!")

        # Parse the output to find the best device
        best_device_index = -1
        max_channels = -1
        for device in devices:
            if device["max_input_channels"] > max_channels:
                device_name = device["name"]
                best_device_index = device["index"]
                max_channels = device["max_input_channels"]

        if best_device_index == -1:
            print("No suitable audio input device found.")
            return None

        print(f"Using audio input device n༚: {best_device_index} - ({device_name})")
        return best_device_index

    except Exception as e:
        print(f"Error selecting audio device: {e}")
        return None

def get_audio_input_devices(audio):
    """
    Retrieves a list of audio input devices with their details.

    Returns:
        List[dict]: A list of dictionaries, each representing an audio input device.
    """

    devices = []
    # Get the number of available devices
    num_devices = audio.get_device_count()

    for i in range(num_devices):
        device_info = audio.get_device_info_by_index(i)

        # Check if the device is an input device
        if device_info.get('maxInputChannels') > 0:
            devices.append({
                "index": i,
                "name": device_info.get("name"),
                "max_input_channels": device_info.get("maxInputChannels"),
                "default_sample_rate": device_info.get("defaultSampleRate"),
                "host_api": audio.get_host_api_info_by_index(device_info.get("hostApi")).get("name"),
                "details": device_info
            }
          )
    return devices

def calculate_progress_percentage(elapsed_time, duration_in_minutes=DURATION):
    """
    Calculate the progress percentage based on elapsed time and total duration.
    """
    if duration_in_minutes <= 0:
        return 0  # Avoid division by zero
    progress_percentage = round((elapsed_time / (duration_in_minutes * 60)) * 100, 2)
    return min(progress_percentage, 100) # Ensure it doesn't exceed 100%

def audio_recording_loop():
  global stream, frames, percent, elapsed_time
  amplify_rate = args.amplify_rate
  start_time = time.time() # Record start time
  # Select best audio device
  devices = get_audio_input_devices(audio)
  best_device_index = select_best_audio_device(devices)

  if best_device_index is not None:
    stream = audio.open(format=FORMAT,
                        channels=CHANNELS,
                        rate=RATE,
                        input=True,
                        input_device_index=best_device_index,
                        frames_per_buffer=CHUNK
                      )
  else:
    stop_event.set()
    raise Exception("Error: No suitable audio input device found. Exiting.")

  try:
    while not stop_event.is_set():
      data = stream.read(CHUNK, exception_on_overflow=False)
      elapsed_time = time.time() - start_time
      if data:
        # Convert raw audio to numpy array
        audio_array = np.frombuffer(data, dtype=np.int16)
        # Amplify audio
        amplified_audio = np.clip(audio_array * amplify_rate, -32768, 32767).astype(np.int16)
        # Convert back to bytes
        amplified_data = amplified_audio.tobytes()
        frames.append(amplified_data)
        percent = calculate_progress_percentage(elapsed_time)
        send_progress_over_socket({
            "process": "Recording" if not stop_event.is_set() or percent < 100 else "done",
            "elapsed_time": elapsed_time,
            "progress": percent,
          }
        )
        if percent == 100:
          stop_event.set()

  except socket.timeout as e:
    print(f"Socket timeout error: {e}")
  except socket.error as e:
    print(f"Socket error occurred: {e}")
  except Exception as e:
    print(f"Error during audio recording: {e}")
  finally:
    stream.stop_stream()
    stream.close()
    audio.terminate()
    wf = wave.open(os.path.join(args.working_directory, args.outfile), 'wb')
    wf.setnchannels(CHANNELS)
    wf.setsampwidth(audio.get_sample_size(FORMAT))
    wf.setframerate(RATE)
    wf.writeframes(b''.join(frames))
    wf.close()


def setup_socket_connection():
    global client_socket
    client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        time.sleep(1)
        client_socket.connect((args.host, args.port))
        print("•")
    except ConnectionRefusedError:
        print(f"Server ConnectionRefused at {args.host}:{args.port}!")
        stop_event.set()
    except Exception as e:
        print(f"Error setting up socket connection: {e}")
        stop_event.set()

def send_progress_over_socket(progress_object):
    global client_socket
    if client_socket:
        try:
          progress_in_json = json.dumps(progress_object)
          client_socket.sendall(progress_in_json.encode('utf-8'))
        except BrokenPipeError:
            stop_event.set()
            if progress_object["process"] != "done":
              raise Exception("\nSocket connection broken.")
            else:
              print("\ndone. Socket connection closed.")
        except Exception as e:
            raise Exception("Failed to send progress >> {e}")

if __name__ == "__main__":
    setup_socket_connection()
    recording_thread = threading.Thread(target=audio_recording_loop)
    recording_thread.start()

    try:
      while not stop_event.is_set():
        time.sleep(0.1)  # Short delay to prevent busy waiting
    except KeyboardInterrupt:
      stop_event.set()
    finally:
      recording_thread.join()
      if client_socket:
        client_socket.close()
    exit(0)
