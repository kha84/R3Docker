#!/bin/bash
  
# turn on bash's job control
set -m
  
# Start the primary process - Rhasspy3 server
./script/http_server --debug --server asr vosk --server tts piper &

sleep 10
curl -X POST --data 'Привет! Спасибо, что включили меня' 'localhost:13331/tts/speak'
  
# Start the pipeline loop
while true
do
  curl -X POST 'localhost:13331/pipeline/run'
done  

 
# if for whatever reason we dropped out of the loop
# we bring the primary process back into the foreground
# and leave it there
fg %1

