#!/bin/bash
set -e

SCRIPTS_DIR=$PWD   # must be set before any cd, used to find mongo.repo and payment.service

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

dnf install python3 gcc python3-devel -y &>>$LOGS_FILE
VALIDATE $? "installing python3 dependencies"

if ! id roboshop &>>$LOGS_FILE; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>$LOGS_FILE
    VALIDATE $? "creating roboshop user"
else
    echo -e "roboshop user already exists ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
fi

mkdir -p /app &>>$LOGS_FILE
VALIDATE $? "creating app directory"

curl -o /tmp/payment.zip https://roboshop-artifacts.s3.amazonaws.com/payment-v3.zip &>>$LOGS_FILE
VALIDATE $? "downloading payment application"

cd /app
unzip -o /tmp/payment.zip &>>$LOGS_FILE
VALIDATE $? "extracting payment application content"

pip3 install -r requirements.txt &>>$LOGS_FILE
VALIDATE $? "installing python dependencies"

cp $SCRIPTS_DIR/payment.service /etc/systemd/system/payment.service
VALIDATE $? "copying payment service file"

systemctl daemon-reload &>>$LOGS_FILE
VALIDATE $? "reloading systemd"

systemctl enable payment &>>$LOGS_FILE
systemctl restart payment &>>$LOGS_FILE
VALIDATE $? "starting and enabling payment service"