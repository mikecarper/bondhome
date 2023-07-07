## What this does
Provides a way to control [bond devices](https://bondhome.io/) via the current weather, as sun position like sunset, estimated solar power generation, and iphone connected to wifi. Target environment is a [raspberry pi zero w](https://www.raspberrypi.com/products/raspberry-pi-zero-w/) running Raspberry Pi OS Lite (Linux shell).


## How to use
#### Install
```shell
git clone https://github.com/mikecarper/bondhome/
```

#### Step 1. 
Run `deviceaction.sh`. It'll ask you to set any tokens for your devices. The tokens can be found in the bond app on your phone. It should auto discover any bond bridges. The first run will install some needed programs as well (jq, avahi-utils)
```shell
bash ~/bondhome/deviceaction.sh
```

#### Step 2. 
Run `weather.sh`. The first run will install some needed programs as well (jq, bc, hdate). It'll use the location set from the bond app to get weather data.
```shell
bash ~/bondhome/weather.sh
```

#### Step 3. 
Get a collection of commands you'd want to run at various times and conditions. The line after "command to do this again" from the output.
```shell
bash ~/bondhome/deviceaction.sh
```

#### Step 5. 
Edit `iphone.sh` to add in iphone mac address.
```shell
sudo apt install nano
nano ~/bondhome/iphone.sh
```

#### Step 6. 
Run `iphone.sh`. The first run will install some needed programs as well (nmap, tshark). It'll scan the network for your phones. Having the Pi plugged in via ethernet is ideal in this case.
```shell
bash ~/bondhome/iphone.sh
```

#### Step 7. 
Edit `schedulerunner.sh` to match the desired times and conditions from Step 3.
```shell
sudo apt install nano
nano ~/bondhome/schedulerunner.sh
```

#### Step 8.

Edit the crontab to add in new jobs.
```shell
crontab -e
```

This example assumes the username is pi.  

What this will do:  
Do not send email.  
Run `weather.sh` every 30 min to get updated weather data.  
Run `deviceaction.sh` every every 2 hours to scan the local network for new bond stuff.  
Run `schedulerunner.sh` every 5 minutes to do the programmed logic.  
Run `iphone.sh` every 10 minutes to check if iPhones are on the LAN.  
Run `usholidays.sh` At 02:00 the 1st in January to update the year's holidays.  

```shell
MAILTO=""
*/30 * * * * bash /home/pi/bondhome/weather.sh
5 */2 * * * bash /home/pi/bondhome/deviceaction.sh -c
2-59/5 * * * * bash /home/pi/bondhome/schedulerunner.sh
*/10 * * * * bash /home/pi/bondhome/iphone.sh
0 2 1 1 * bash /home/pi/bondhome/usholidays.sh
```

## example weather.sh output
```
Coordinates: 45,-100 (lat,Long)
Valid Weather Time: YYYY-MM-DDTHH:00:00 UNIXTIME
Weather Data Good Until:YYYY-MM-DDTHH:MM:SS UNIXTIME
Generated time: 11:19 -TZ UNIXTIME
sunrise: 05:09 -TZ UNIXTIME
sunset: 21:07 -TZ UNIXTIME
midday: 13:08 -TZ UNIXTIME

Heat Index: 50 F
Apparent Temperature: 49 F
Temperature: 51 F
Max Temperature: 72 F
Min Temperature: 49 F
Relative Humidity: 85 %

Sky Cover Now: 98 %
Average Sky Cover Morning: 96 %
Average Sky Cover Afternoon: 94 %
Solar Watt Now: 99 (1kw system)
Solar Watt Hours Today: 918 (1kw system)
Solar Watt Hours Morning: 498 (1kw system)
Solar Watt Hours Afternoon: 416 (1kw system)
Probability of Precipitation: 64 %
Quantitative Precipitation: 0.00 in

Wind: 4.6 mph
Wind Gust: 6.9 mph
Transport Wind: 5.8 mph
Max Wind: 6.9 mph

pm10: 8.5
pm25: 5.6
carbon_monoxide: 139
nitrogen_dioxide: 2.9
sulphur_dioxide: 3.2
ozone: 122
aerosol_optical_depth: 0.08
dust: 0
uv_index: 6.7
uv_index_clear_sky: 6.75

Ozone AQI: 0 Good Green
PM2.5 AQI: 23 Good Green
PM10 AQI: 8 Good Green
CO AQI: 2 Good Green
NO2 AQI: 3 Good Green
SO2 AQI: 4 Good Green
```
