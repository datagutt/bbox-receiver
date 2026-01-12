# Belabox SRTLA receiver

***Provided by [IRLServer](https://irlserver.com)***

SRTLA Belabox receiver with support for multiple streams and per-stream authentication.

This Docker container is kept semi up-to-date, but is only community-supported.
It is used by multiple streamers around the world, but I am using a different setup for paid production services.

**WARNING: This is not an official Belabox project. Please don't spam rationalirl about it!**

We using the following great open-source projects:

- srt from <https://github.com/IRLServer/srt>
- srtla_rec from <https://github.com/IRLServer/srtla>
- irl-srt-server (srt-live-server fork) from <https://github.com/IRLServer/irl-srt-server>

These [IRLServer](https://irlserver.com)-supported forks have enhanced algorithms and improvements to enhance stream stability.

## Manual

It requires the following ports to be published:

5000:5000/udp
8181/8181/tcp
8282/8282/udp
3000/3000/tcp

Create a config.json file containing:

```json
{
  "auth": [
    {
      "user": "belabox",
      "key": "belabox"
    },
    {
      "user": "second_user",
      "key": "secret_key"
    }
  ]
}
```

Modify everything in bold below, then start with:

docker run -d --name belabox-receiver -p 5000:5000/udp -p 8181:8181/tcp -p 8282:8282/udp -p 3000:3000/tcp -v ./config.json:/app/config.json datagutt/belabox-receiver:latest

Configure SRT receiver and SRT port within belabox to point to the docker container's IP address (or a port-forward on your router).
Within Belabox, set "live/stream/belabox?srtauth=belabox" as SRT streamid.

To retrieve the SRT-Stream (via OBS, VLC etc.), open the following URL:
srt://your-public-container-ip:8282/?streamid=play/stream/belabox?srtauth=belabox

Statistics-URL: <http://your-public-container-ip:8181/stats?publisher=live%2Fstream%2Fbelabox%3Fsrtauth%3Dbelabox>

Legacy Statistics-URL: <http://your-public-container-ip:3000/stats?streamer=belabox&key=belabox>
