# whisper_api.py
import argparse
import whisper
from whisper.utils import format_timestamp, get_writer, WriteTXT
import numpy as np
import torch
import math
import os
import subprocess
from openai import OpenAI
from pydub import AudioSegment
from pydub.silence import split_on_silence

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audio_file", required=True)
    parser.add_argument("--task", default="transcribe")
    parser.add_argument("--api_key", required=True)
    parser.add_argument("--language", default="Auto-Detect")
    parser.add_argument("--prompt", default=None)
    parser.add_argument("--output_formats", default="json")
    parser.add_argument("--output_dir", default=".")  # Default to current directory

    args = parser.parse_args()
    # --- API call and processing (adapt from original notebook) ---
    api_client = OpenAI(api_key=args.api_key)

    api_supported_formats = ['mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'wav', 'webm']
    api_max_bytes = 25 * 1024 * 1024 # 25 MB

    api_transcribe = api_client.audio.transcriptions if args.task == 'transcribe' else api_client.audio.translations
    api_transcribe = api_transcribe.create

    api_model = 'whisper-1' # large-v2

      # https://platform.openai.com/docs/api-reference/audio?lang=python
    api_options = {
        'response_format': 'verbose_json',
    }

    if args.prompt:
        api_options['prompt'] = args.prompt

    api_options['temperature'] = 0.0

    # detect language
    detect_language = not args.language or args.language == "Auto-Detect"

    if not detect_language:
        api_options['language'] = whisper.tokenizer.TO_LANGUAGE_CODE.get(args.language.lower())

    if args.task == "transcribe" and not detect_language:
        api_options['language'] =  whisper.tokenizer.TO_LANGUAGE_CODE.get(args.language.lower())

    source_audio_name_path, source_audio_ext = os.path.splitext(args.audio_file)
    source_audio_ext = source_audio_ext[1:]

    if source_audio_ext in api_supported_formats:
        api_audio_path = args.audio_file
        api_audio_ext = source_audio_ext
    else:
        ## convert audio file to a supported format
        print(f"API supported formats: {','.join(api_supported_formats)}")
        print(f"Converting {source_audio_ext} audio to a supported format...")

        api_audio_ext = 'mp3'

        api_audio_path = f'{source_audio_name_path}.{api_audio_ext}'

        subprocess.run(['ffmpeg', '-i', args.audio_file, api_audio_path], check=True, capture_output=True)

        print(api_audio_path, end='\n\n')
    ## split audio file in chunks
    api_audio_chunks = []
    audio_bytes = os.path.getsize(api_audio_path)

    if audio_bytes >= api_max_bytes:
        print(f"Audio exceeds API maximum allowed file size.\nSplitting audio in chunks...")

        audio_segment_file = AudioSegment.from_file(api_audio_path, api_audio_ext)

        min_chunks = math.ceil(audio_bytes / (api_max_bytes / 2))

        # print(f"Min chunks: {min_chunks}")

        max_chunk_milliseconds = int(len(audio_segment_file) // min_chunks)

        # print(f"Max chunk milliseconds: {max_chunk_milliseconds}")

        def add_chunk(api_audio_chunk):
            api_audio_chunk_path = f"{source_audio_name_path}_{len(api_audio_chunks) + 1}.{api_audio_ext}"
            api_audio_chunk.export(api_audio_chunk_path, format=api_audio_ext)
            api_audio_chunks.append(api_audio_chunk_path)

        def raw_split(big_chunk):
            subchunks = math.ceil(len(big_chunk) / max_chunk_milliseconds)

            for subchunk_i in range(subchunks):
                chunk_start = max_chunk_milliseconds * subchunk_i
                chunk_end = min(max_chunk_milliseconds * (subchunk_i + 1), len(big_chunk))
                add_chunk(big_chunk[chunk_start:chunk_end])

        non_silent_chunks = split_on_silence(audio_segment_file,
                                            seek_step=5, # ms
                                            min_silence_len=1250, # ms
                                            silence_thresh=-25, # dB
                                            keep_silence=True) # needed to aggregate timestamps
        # print(f"Non silent chunks: {len(non_silent_chunks)}")

        current_chunk = non_silent_chunks[0] if non_silent_chunks else audio_segment_file

        for next_chunk in non_silent_chunks[1:]:
            if len(current_chunk) > max_chunk_milliseconds:
                raw_split(current_chunk)
                current_chunk = next_chunk
            elif len(current_chunk) + len(next_chunk) <= max_chunk_milliseconds:
                current_chunk += next_chunk
            else:
                add_chunk(current_chunk)
                current_chunk = next_chunk

        if len(current_chunk) > max_chunk_milliseconds:
            raw_split(current_chunk)
        else:
            add_chunk(current_chunk)

        print(f'Total chunks: {len(api_audio_chunks)}\n')

    else:
        api_audio_chunks.append(api_audio_path)


    # --- process chunks ---
    result = None

    for api_audio_chunk_path in api_audio_chunks:
        ## API request
        with open(api_audio_chunk_path, 'rb') as api_audio_file:
            api_result = api_transcribe(model=api_model, file=api_audio_file, **api_options)
            api_result = api_result.model_dump() # to dict

        api_segments = api_result['segments']

        if result:
            ## update timestamps
            last_segment_timestamp = result['segments'][-1]['end'] if result['segments'] else 0

            for segment in api_segments:
                segment['start'] += last_segment_timestamp
                segment['end'] += last_segment_timestamp

            ## append new segments
            result['segments'].extend(api_segments)

            if 'duration' in result:
                result['duration'] += api_result.get('duration', 0)
        else:
            ## first request
            result = api_result
            if detect_language:
                print(f"Detected language: {result['language'].title()}\n")

        #display segments
        for segment in api_segments:
             print(f"[{format_timestamp(segment['start'])} --> {format_timestamp(segment['end'])}] {segment['text']}")


     # fix results formatting
    for segment in result['segments']:
        segment['text'] = segment['text'].strip()

    result['text'] = '\n'.join(map(lambda segment: segment['text'], result['segments']))

    output_file_name = os.path.splitext(os.path.basename(args.audio_file))[0]
    output_formats = args.output_formats.split(',')

    # write result in the desired format
    for output_format in output_formats:
        output_format = output_format.strip()

        if output_format == 'txt