# Laravel deploy

A bash script to deploy Laravel projects.

## Usage

Go to project `parent` directory and paste following commands:

```bash
rm -fv ./deploy.sh
wget -N https://raw.githubusercontent.com/alirezamaleky/laravel-deploy/master/deploy.sh
chmod +x ./deploy.sh
./deploy.sh -t deploy -p folder
```

## Options

```
-p --path <path>    (folder path)
-t --target deploy  (optional, if not set just workspace will load)
-u --update         (force install project libraries even if not changed.)
-f --format         (remove everything and fresh install docker and project)
```
