#!/bin/bash
set -e

SCRIPTS_DIR=$PWD   # must be set before any cd, used to find mongo.repo and catalogue.service

LOGS_FOLDER="/var/log/roboshop"
sudo mkdir -p $LOGS_FOLDER
sudo chown -R ec2-user:ec2-user $LOGS_FOLDER
sudo chmod -R 755 $LOGS_FOLDER
LOGS_FILE="$LOGS_FOLDER/$(basename $0).log"

USER_ID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

trap 'echo "error at line $LINENO, command: $BASH_COMMAND"' ERR

# check root access or not
if [ $USER_ID -ne 0 ]; then
    echo -e "${R}please run this script with root access${N}"
    exit 1
fi

VALIDATE(){
    if [ $1 -ne 0 ]; then
        echo -e "$2 ... $R [FAILED] $N" | tee -a $LOGS_FILE
        exit 1
    else
        echo -e "$2 ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
    fi
}

dnf module disable nodejs -y &>>$LOGS_FILE
dnf module enable nodejs:20 -y &>>$LOGS_FILE
dnf install nodejs -y &>>$LOGS_FILE
VALIDATE $? "installing nodejs:20"

if ! id roboshop &>>$LOGS_FILE; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>$LOGS_FILE
    VALIDATE $? "creating roboshop user"
else
    echo -e "roboshop user already exists ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
fi

mkdir -p /app &>>$LOGS_FILE
VALIDATE $? "creating app directory"

curl -o /tmp/catalogue.zip https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip &>>$LOGS_FILE
VALIDATE $? "downloading catalogue application"

cd /app
unzip -o /tmp/catalogue.zip &>>$LOGS_FILE
VALIDATE $? "extracting catalogue application content"

npm install &>>$LOGS_FILE
VALIDATE $? "installing nodejs dependencies"

cp $SCRIPTS_DIR/catalogue.service /etc/systemd/system/catalogue.service
VALIDATE $? "copying catalogue service file"

systemctl daemon-reload &>>$LOGS_FILE
VALIDATE $? "reloading systemd"

cp $SCRIPTS_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "adding mongo repo"

dnf install mongodb-mongosh -y
VALIDATE $? "installing mongodb client"

INDEX=$(mongosh --host mongodb.rakesh08.online --quiet --eval 'db.getMongo().getDBNames().indexOf("catalogue")')

if [ $INDEX -lt 0 ]; then
    mongosh --host mongodb.rakesh08.online </app/db/master-data.js &>>$LOGS_FILE
    VALIDATE $? "loading catalogue schema"
else
    echo -e "catalogue schema already loaded ... $Y [SKIPPING] $N" | tee -a $LOGS_FILE
fi

systemctl enable catalogue &>>$LOGS_FILE
systemctl restart catalogue &>>$LOGS_FILE
VALIDATE $? "starting and enabling catalogue service"