## Rhasspy3 docker image creator

When you need to run a rich sound application like Rhasspy3 in a docker container there's a number of things you need to keep in mind and there're number of options to choose from.
The purpose of this script is to detect your host configuration, create a proper docker image of Rhasspy3 and start a container out of it, to let run Rhasspy3 smoothly whether you're running bare ALSA, Pulseaudio or Pipewire:

* if you're running Rhasspy3 on a barebone system or as one and only sound application without any sound server being present (pure ALSA) - the script will help you to identify proper input/output ALSA devices and configure them to be used by Rhasspy

* it might get a bit tricky if you're also planning to run any additional sound applications on your host through the same ALSA devices. Like browsing the web, watching moveis or listening to music. These ALSA devices might get occasionally locked either by Rhasspy or by your sound software - so they will be clashing one into another. In order to overcome that, we'll need to setup ALSA DMIX plugin (this script will help to do that, but this is yet TODO)

* if you're running Pulseaudio or Pipewire sound servers, the script will help to configure Rhasspy3 to use them properly: to pass the proper sockefile down to the Rhasspy3 container. The same audio input/output devices can be still used on your host, as Pipewire/Pulseaudio provides sound mixing capabilities out of the box.

## Usage

Make sure you have `docker` and `alsa-utils` installed. Then:

```
git clone ....
cd xxxx
./runme.sh
```

Script asks you a series of questions. Based on your answers it creates a docker image and then starts a container with Rhasspy3 out of that image.

## TODO

* add some interactive tests for user, if he's using Pipewire or Pulseaudio - to make sure the currently selected sink/source devices are fine

* guide user to configure DMIX plugin if he uses just bare ALSA

* deal with Pipewire/Pulseaudio started under desktop manager user (gdm, sddm), before user logs in interactively. Possible options are: 1) to configure PW/PA server to use the same location of the sockefile, so it doesn't matter what user is running them, the socketfile will be the same. 2) to configure PW/PA server on a host to accept local network connections and use pulseaudio/pipewire client in a docker container that will be utilizing that. So again, it won't matter if it's `gdm` who is running Pipewire/Pulseaudio or your own user - they both should accept network connections out of docker container

* to switch from `Ubuntu:22.04` image as a base to `Alpine`
