## What this does
Provides a way to control [bond devices](https://bondhome.io/) via the current weather as well as sun position like sunset. Target environment is a [raspberry pi zero w](https://www.raspberrypi.com/products/raspberry-pi-zero-w/) running Raspberry Pi OS Lite (Linux shell).


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
Get a collection of commands you'd want to run at various times and conditions.
```shell
bash ~/bondhome/deviceaction.sh
```

#### Step 4. 
Edit `schedulerunner.sh` to match the desired times and conditions from Step 3.
```shell
sudo apt install nano
nano ~/bondhome/schedulerunner.sh
```

#### Example cronjob.
This example assumes the username is pi.  
Do not send email.  
Run `weather.sh` every 30 min to get updated weather data.  
Run `deviceaction.sh` every every 2 hours to scan the local network for new bond stuff.  
Run `schedulerunner.sh` every 5 minutes to do the programmed logic.  

```shell
MAILTO=""
*/30 * * * * bash /home/pi/bondhome/weather.sh
5 */2 * * * bash /home/pi/bondhome/deviceaction.sh -c
2-59/5 * * * * bash /home/pi/bondhome/schedulerunner.sh
```
