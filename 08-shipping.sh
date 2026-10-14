#!/bin/bash
set -e

SCRIPTS_DIR=$PWD   # must be set before any cd, used to find mongo.repo and shipping.service

LOGS_FOLDER="/var/log/roboshop"
sudo mkdir -p $LOGS_FOLDER
sudo chown -R ec2-user:ec2-user $LOGS_FOLDER
sudo chmod -R 755 $LOGS_FOLDER
LOGS_FILE="$LOGS_FOLDER/$(basename $0).log"
SCRIPT_DIR=$PWD
MYSQL_HOST=mysql.rakesh08.online

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

dnf install maven -y &>>$LOGS_FILE
VALIDATE $? "installing maven"

if ! id roboshop &>>$LOGS_FILE; then
    useradd --system --home /app --shell /sbin/nologin --comment "roboshop system user" roboshop &>>$LOGS_FILE
    VALIDATE $? "creating roboshop user"
else
    echo -e "roboshop user already exists ... $G [SUCCESS] $N" | tee -a $LOGS_FILE
fi

mkdir -p /app &>>$LOGS_FILE
VALIDATE $? "creating app directory"

curl -o /tmp/shipping.zip https://roboshop-artifacts.s3.amazonaws.com/shipping-v3.zip &>>$LOGS_FILE
VALIDATE $? "downloading shipping application"

cd /app
unzip -o /tmp/shipping.zip &>>$LOGS_FILE
VALIDATE $? "extracting shipping application content"

mvn clean package &>>$LOGS_FILE
mv target/shipping-1.0.jar shipping.jar
VALIDATE $? "building shipping application"

cp $SCRIPTS_DIR/shipping.service /etc/systemd/system/shipping.service
VALIDATE $? "copying shipping service file"

dnf install mysql -y &>>$LOGS_FILE
VALIDATE $? "installing mysql client"

mysql -h $MYSQL_HOST -uroot -pRoboShop@1 -e "use cities" &>>$LOGS_FILE
if [ $? -ne 0 ]; then
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 </app/db/schema.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 </app/db/app-user.sql
    mysql -h $MYSQL_HOST -uroot -pRoboShop@1 </app/db/master-data.sql
    VALIDATE $? "data loaded"
else
    echo -e "shipping schema already loaded ... $Y [SKIPPING] $N"
fi

systemctl daemon-reload &>>$LOGS_FILE
VALIDATE $? "reloading systemd"

systemctl enable shipping &>>$LOGS_FILE
systemctl restart shipping &>>$LOGS_FILE
VALIDATE $? "starting and enabling shipping service"