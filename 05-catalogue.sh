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

dnf module disable nodejs -y &>>$LOGS_FILE
dnf module enable nodejs:20 -y &>>$LOGS_FILE
dnf install nodejs -y &>>$LOGS_FILE
VALIDATE $? "installing nodejs:20" 

id roboshop &>>$LOGS_FILE
if [ $? -ne 0 ]; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>$LOGS_FILE
    VALIDATE $? "creating roboshop user"
else
    echo -e "roboshop user already exists ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
fi

mkdir -p /app &>>$LOGS_FILE
VALIDATE $? "creating app directory"

curl -o /tmp/catalogue.zip https://roboshop-artifacts.s3.amazonaws.com/catalogue-v3.zip 
cd /app
unzip /tmp/catalogue.zip &>>$LOGS_FILE
VALIDATE $? "downloading and extracting catalogue application content"

npm install &>>$LOGS_FILE
VALIDATE $? "installing nodejs dependencies"

cp $SCRIPTS_DIR/mongo.repo /etc/yum.repos.d/mongo.repo
VALIDATE $? "adding mongo repo"

dnf install mongodb-mongosh -y &>>$LOGS_FILE
VALIDATE $? "installing mongodb client"

INDEX=$(mongosh --host mongodb-rakesh08.shop --quiet --eval 'db.getMongo().getDBNames().indexOf("catalogue")')

if [ $INDEX -lt 0 ]; then
    mongosh --host mongodb-rakesh08.shop </app/db/master-data.js &>>$LOGS_FILE
    VALIDATE $? "loading catalogue schema"
else
    echo -e "catalogue schema already loaded ... $Y [SKIPPING] $N" | tee -a $LOGS_FILE
fi

systemctl enable catalogue &>>$LOGS_FILE
systemctl restart catalogue &>>$LOGS_FILE
VALIDATE $? "starting and enabling catalogue service"