#!/bin/bash
set -e

SCRIPTS_DIR=$PWD   # must be set before any cd, used to find mongo.repo and frontend.service

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

dnf module disable nginx -y &>>$LOGS_FILE
dnf module enable nginx:1.24 -y &>>$LOGS_FILE
dnf install nginx -y &>>$LOGS_FILE
VALIDATE $? "installing nginx"

systemctl enable nginx &>>$LOGS_FILE
systemctl start nginx &>>$LOGS_FILE
VALIDATE $? "starting and enabling nginx service"

rm -rf /usr/share/nginx/html/* &>>$LOGS_FILE
VALIDATE $? "removing default nginx content"

curl -o /tmp/frontend.zip https://roboshop-artifacts.s3.amazonaws.com/frontend-v3.zip &>>$LOGS_FILE
VALIDATE $? "downloading frontend application"

cd /usr/share/nginx/html
unzip -o /tmp/frontend.zip &>>$LOGS_FILE
VALIDATE $? "extracting frontend application content"

cp $SCRIPTS_DIR/frontend.service /etc/systemd/system/frontend.service
VALIDATE $? "copying frontend service file"

systemctl enable frontend &>>$LOGS_FILE
systemctl restart frontend &>>$LOGS_FILE
VALIDATE $? "starting and enabling frontend service"