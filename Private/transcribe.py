from faster_whisper import WhisperModel
import threading
import argparse
import time
import os

parser = argparse.ArgumentParser(description='Audio file  to text with Socket Output')
parser.add_argument('--inputfile', type=str, help='Input audio file')
parser.add_argument('--outfile', type=str, default=time.strftime("%Y%m%d-%H%M%S") + "_output.txt", help='Output text file for the transcribed audio')
parser.add_argument('--working-directory', type=str, default=os.getcwd(), help='Working directory for the script')
args = parser.parse_args()

model_size: str = "large-v3"
stop_event: threading.Event = threading.Event()

def get_text_from_audio(input_audio_file: str, output_text_file: str) -> None:
    # or run on CPU with INT8
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    print("• transcribing...")
    segments, info = model.transcribe(input_audio_file, beam_size=5)
    print("Detected language '%s' with probability %f" % (info.language, info.language_probability))

    with open(output_text_file, "w") as outfile:
        for segment in segments:
            text_to_print = "[%.2fs -> %.2fs] %s\n" % (
                segment.start,
                segment.end,
                segment.text,
            )
            print(text_to_print.strip())
            outfile.write(segment.text)

    print("• transcription done!")

if __name__ == "__main__":
    transcribe_thread = threading.Thread(target=get_text_from_audio, args=(args.inputfile, args.outfile))
    transcribe_thread.start()

    try:
      while not stop_event.is_set():
        time.sleep(0.1)  # Short delay to prevent busy waiting
    except KeyboardInterrupt:
      stop_event.set()
    finally:
      transcribe_thread.join()
    exit(0)
