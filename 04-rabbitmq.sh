#!/bin/bash
set -e

LOGS_FOLDER="/var/log/roboshop"
sudo mkdir -p $LOGS_FOLDER
sudo chown -R ec2-user:ec2-user $LOGS_FOLDER
sudo chmod -R 755 $LOGS_FOLDER
LOGS_FILE="$LOGS_FOLDER/$0.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

USER_ID=$(id -u)
R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

trap 'echo "error at $LINENO", command: $BASH_COMMAND"' ERR

#check root access or not
if [ $USER_ID -ne 0 ]; then
    echo -e "${R}please run this script with root access"
    exit 1
fi

VALIDATE(){
    if [ $1 -ne 0 ]; then
     echo -e "$2 ... $R [FAILED] $N" | tee -a $LOGS_FILE
    else
     echo -e "$2 ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
    fi
}

cp rabbitmq.repo /etc/yum.repos.d/rabbitmq.repo &>>$LOGS_FILE
VALIDATE $? "Adding rabbitmq repo"

dnf install rabbitmq-server -y &>>$LOGS_FILE
VALIDATE $? "Installing rabbitmq-server"

systemctl enable rabbitmq-server &>>$LOGS_FILE
systemctl start rabbitmq-server &>>$LOGS_FILE
VALIDATE $? "starting and enabling rabbitmq-server service"

rabbitmqctl add_user roboshop Roboshop@1 &>>$LOGS_FILE
rabbitmqctl set_permissions -p / roboshop ".*" ".*" ".*" &>>$LOGS_FILE
VALIDATE $? "setting up username and password for rabbitmq-server"