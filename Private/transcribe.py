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
    # run on CPU with INT8
    model = WhisperModel(model_size, device="cpu", compute_type="int8")
    print(f"  ● Transcribing '{input_audio_file}'...")
    segments, info = model.transcribe(input_audio_file, beam_size=5)
    print("  ┆ Detected language '%s' with P(A): %f" % (info.language.upper(), info.language_probability))

    with open(output_text_file, "w") as outfile:
        for segment in segments:
            # For debug purposes:
            # text_to_print = "[%.2fs -> %.2fs] %s\n" % (
            #     segment.start,
            #     segment.end,
            #     segment.text,
            # )
            # print(text_to_print.strip())
            outfile.write(segment.text)
    print("  ● done.")
    return

if __name__ == "__main__":
  get_text_from_audio(args.inputfile, args.outfile)
  exit(0)
