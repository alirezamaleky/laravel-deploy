# Laravel deploy

A bash script to deploy Laravel projects.

## Get start

First install following packages:

```bash
apt install -y cron curl htop make nano tmux unrar unzip vim wget
```

- [Git](https://github.com/alirezamaleky/handbook/blob/master/Git.md)
- [Docker](https://github.com/alirezamaleky/handbook/blob/master/Docker.md)

## Usage

Go to project directory and paste following commands:

```bash
rm -f ./deploy.sh
wget -N https://raw.githubusercontent.com/alirezamaleky/laravel-deploy/master/deploy.sh
chmod +x ./deploy.sh
./deploy.sh -t deploy -d project_folder
```
