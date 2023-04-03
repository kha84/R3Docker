#!/bin/bash

# Define the name of the Docker image you want to delete
IMAGE_NAME="rhasspy3"

continue_prompt() {
    echo "$1"
    read -p "Press Y to continue, or any other key to exit: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "User has chosen to continue."
    else
        echo "User has chosen to exit. Exiting script..."
        exit 1
    fi
}

#######################################################
# Sanity checks before running the rest of the script #
#######################################################

# ensure we're running the script not as root user
if [ "$(id -u)" -eq "0" ]; then
  echo "Run this script as a normal user, not as root"
  exit 1
fi

# check we have docker installed
command -v docker >/dev/null 2>&1 || { echo >&2 "Error: docker is required but it's not installed. "; exit 1; }

# ensure current user is in docker group
id | grep -q "(docker)" || { echo >&2 "Error: current user is not in the 'docker' group. Consider to run as root: usermod -a -G docker $USER"; exit 1; }

# ensure current user is in audio group
id | grep -q "(audio)" || { echo >&2 "Error: current user is not in the 'audio' group. Consider to run as root: usermod -a -G audio $USER"; exit 1; }


#######################################################
# Deal with the current sound setup of user host      #
# Once we're done, we should have next vars defined:  #
#  - SOUND_SERVER                                     #
#  - alsa_input_device                                #
#  - alsa_output_device                               #
#######################################################

# check what sound server we do have running
if [[ -e "/run/user/$(id -u)/pulse/native" ]]; then
  echo "Looks like we're running Pulseaudio: found a unix socket file /run/user/$(id -u)/pulse/native" 
  echo "Let's ask pactl what will it tell us"
  command -v pactl>/dev/null 2>&1 || { echo >&2 "Error: 'pactl' is required to figure out what sound server you host is running, but it's not installed. Please consider to install it. Aborting."; exit 1; }
  pa_server_name=$(pactl info | grep -oP "Server Name: \K.*")
  if echo "$pa_server_name" | grep -iq "pipewire" ; then
    echo "Your host is actually running Pipewire as main sound server. PulseAudio is there just for compatibility. But the primary thing is stil Pipewire. We are going to use that"
    SOUND_SERVER=pipewire
    alsa_input_device=pipewire
    alsa_output_device=pipewire
  else
    echo "Your host is running Pulseaudio as main sound server"
    SOUND_SERVER=pulse
    alsa_input_device=pulse
    alsa_output_device=pulse
  fi
elif [[ -e "/run/user/$(id -u)/pipewire-0" ]]; then
  echo "Looks like we're running Pipewire: found a unix socket file /run/user/$(id -u)/pipewire-0"
  SOUND_SERVER=pipewire
  alsa_input_device=pipewire
  alsa_output_device=pipewire
else
  echo "Sound server unix socket file is not found for current user. Using ALSA mode"
  pgrep -x pipewire && echo "Warning: Pipewire is found running (prob under user other than $USER). It might be locking ALSA devices"
  pgrep pulseaudio && echo "Warning: Pulseaudio is found running (prob under user other than $USER). It might be locking ALSA devices"
  SOUND_SERVER=alsa
fi
continue_prompt "Do you want to continue with the suggested settings?"

#######################################################
# Now lets give user a chance to test his audio:      #
# we are going to test the output device first        #
# and once it has been selected we are going to test  #
# the input device                                    #
#######################################################


# if user selected ALSA, let him pick proper ALSA PCM devices for input and output
if [ "$SOUND_SERVER" == "alsa" ]; then

  # Check if aplay and speaker-test are installed
  command -v aplay >/dev/null 2>&1 || { echo >&2 "Error: aplay is required but it's not installed. Aborting."; exit 1; }
  command -v arecord >/dev/null 2>&1 || { echo >&2 "Error: arecord is required but it's not installed. Aborting."; exit 1; }
  command -v speaker-test >/dev/null 2>&1 || { echo >&2 "Error: speaker-test is required but it's not installed. Aborting."; exit 1; }

  # warn user before we continue
  continue_prompt "We are going to test all your ALSA playback devices to see which one is the right one to use. Please connect your speaker device you want to use with Rhasspy3"
  
  # Loop through all ALSA playback devices for the current user
  for dev in $(aplay -L | grep -o 'sysdefault:CARD=.*')
  do
    # Test the device with speaker-test
    echo "Testing device $dev..."
    if speaker-test -D "$dev" -c 2 -l 1 -t wav; then
      # If the user confirms that they can hear the sound, output the device name and exit
      read -p "Do you hear the sound? (Y/N) " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Selected output device: $dev"
        alsa_output_device=$dev
        break
      fi
    fi
  done
  
  # if no output device was found - exit here
  if [ "$alsa_output_device" == "" ]; then
    echo "No suitable ALSA output device was found. Make sure the device you intended to use with Rhasspy3 is not being used by any other application"
    exit 1
  fi

  # Loop through all ALSA capture devices for the current user
  for dev in $(arecord -L | grep -o 'sysdefault:CARD=.*')
  do
    # Record a short audio snippet using the device
    echo "We're going to test device $dev"
    read -p "Press any button when ready and start speaking right after..." -n 1 -r
    echo
    if arecord -D "$dev" -c 1 -d 3 -f S16_LE -r 16000 test.wav; then
        # Play back the recorded audio snippet
        echo "Playing back the recorded audio..."
        if aplay -D "$alsa_output_device" test.wav; then
            # If the user confirms that they can hear the sound, output the device name and exit
            read -p "Do you hear the sound? (Y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Selected input device: $dev"
                echo "Hint: if the microphone sound was distorted, consider to run 'alsamixer' and lower microphone boost and gain"
                alsa_input_device=$dev
                break
            fi
        fi
    fi
  done

  # if no output device was found - exit here
  if [ "$alsa_input_device" == "" ]; then
    echo "Error: no suitable ALSA input device was found. Make sure the device you intended to use with Rhasspy3 is not being used by any other application"
    exit 1
  fi

elif [ "$SOUND_SERVER" == "pipewire" ]; then

  echo "Sorry, testing of pipewire devices was not yet implemented"
  # TODO

elif [ "$SOUND_SERVER" == "pulse" ]; then

  echo "Sorry, testing of Pulseaudio devices was not yet implemented"
  # TODO

fi



#######################################################
# Support for cyrillic console and TTS/ASR models     #
#######################################################

# If the user confirms that they can hear the sound, output the device name and exit
read -p "Install russian locales and ASR/TTS models? (Y/N) " -n 1 -r
echo
dockerfile="Dockerfile-en"
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Cyrillic support will be enabled"
    dockerfile="Dockerfile-ru"
fi
echo "Dockerfile $dockerfile will be used to create an image"


#######################################################
# Create a docker image                               #
#######################################################

# Check if the image exists
if docker image ls | awk '{print $1}' | grep -q "^$IMAGE_NAME$"; then
    # ask user
    continue_prompt "Found an existing docker image $IMAGE_NAME. Do you want to delete it?"
    # Delete any containers based on the image
    docker container ls -a | awk '{print $1,$2}' | grep "$IMAGE_NAME" | awk '{print $1}' | xargs -I {} docker container rm -f {}
    # Delete the image
    docker image rm $IMAGE_NAME
    echo "Deleted $IMAGE_NAME image and its containers"
else
    echo "$IMAGE_NAME image not found. That's good because we're going to create one"
fi

# building an image
docker build -t $IMAGE_NAME -f $dockerfile --build-arg alsa_input_device=$alsa_input_device --build-arg alsa_output_device=$alsa_output_device .
ec=$?
if [ $ec -ne 0 ]; then
  echo "Error: building an image failed"
  exit 1
fi

#######################################################
# Create a docker container out of the fresh image    #
#######################################################

# starting a container
if [ "$SOUND_SERVER" == "pipewire" ]; then
    docker run -d -v /run/user/1000/pipewire-0:/tmp/pipewire-0 -e XDG_RUNTIME_DIR=/tmp --publish 13331:13331 $IMAGE_NAME
    ec=$?
elif [ "$SOUND_SERVER" == "pulse" ]; then
    docker run -d -v /run/user/1000/pulse/native:/run/user/1000/pulse/native -e PULSE_SERVER=unix:/run/user/1000/pulse/native --publish 13331:13331 $IMAGE_NAME  
    ec=$?
elif [ "$SOUND_SERVER" == "alsa" ]; then
    docker run -d --device /dev/snd --publish 13331:13331 $IMAGE_NAME  
    ec=$?
else
    echo "Error: SOUND_SERVER=$SOUND_SERVER was not expected here"
    exit 1
fi

# make sure container was started
if [ $ec -ne 0 ]; then
  echo "Error: starting container failed"
  exit 1
fi

# Get the name of the most recently created container
CONTAINER_NAME=$(docker ps --format '{{.Names}} {{.CreatedAt}}' | sort -r -k 2 | head -n1 | awk '{print $1}')

echo
echo "****************************************************"
echo "Container [$CONTAINER_NAME] was successfully created"
echo "****************************************************"
echo
echo "# you can now speak to it by saying: porcupine <pause> <any text>"
echo "# it should respond you back with everything you said"
echo
echo "# to see its logs"
echo "docker logs $CONTAINER_NAME -f"
echo
echo "# to jump into that container"
echo "docker exec --user root -it $CONTAINER_NAME bash"
echo
echo "# to make a call to ASR or TTS"
echo "curl -X POST 'localhost:13331/pipeline/run'"

# echo "**************************************"
# echo "1) run this command:"
# echo ""
# echo "  script/run bin/pipeline_run.py --debug"
# echo ""
# echo "2) wait for a while then say: porcupine <any text>"

#docker run -v /run/user/1000/pipewire-0:/tmp/pipewire-0 -e XDG_RUNTIME_DIR=/tmp --publish 13331:13331 rhasspy3
#docker run -it -v /run/user/1000/pipewire-0:/tmp/pipewire-0 -e XDG_RUNTIME_DIR=/tmp --publish 13331:13331 --name rhasspy3 ubuntu /bin/bash


# start the server
# script/http_server --debug --server asr vosk --server tts piper &

# curl -X POST --data 'Welcome to the world of speech synthesis.' 'localhost:13331/tts/speak'

# curl -X POST 'localhost:13331/pipeline/run'
# curl -X POST 'localhost:13331/pipeline/run?start_after=wake'

# sysdefault:CARD=Generic_1
