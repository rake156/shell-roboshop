#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z0702543JR335XUHBX9I" # replace with your zone ID
DOMAIN_NAME=rakesh08.online # replace with your domain

for instance in $@
do
    INSTANCE_ID=$(get_instance_id $instance)

    if [ "$ACTION" == "create" ]; then
        if [ "$INSTANCE_ID" == "None" ]; then
            echo "Launching Instance: roboshop-$instance"

            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id $AMI_ID \
                --instance-type t3.micro \
                --security-groups "roboshop-common" "roboshop-$instance" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
                --query 'Instances[0].InstanceId' \
                --output text)

            echo "Launched Instance: $INSTANCE_ID"

            # update R53 record
            if [ "$instance" == "frontend" ]; then
                IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' \
                    --output text)
                R53_RECORD="$DOMAIN_NAME"
            else
                IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
                    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                    --output text)
                R53_RECORD="$instance.$DOMAIN_NAME"
            fi

            aws route53 change-resource-record-sets \
                --hosted-zone-id $ZONE_ID \
                --change-batch "{
                    \"Changes\": [{
                        \"Action\": \"UPSERT\",
                        \"ResourceRecordSet\": {
                            \"Name\": \"$R53_RECORD\",
                            \"Type\": \"A\",
                            \"TTL\": 1,
                            \"ResourceRecords\": [{
                                \"Value\": \"$IP\"
                            }]
                        }
                    }]
                }"

        else
            echo "roboshop-$instance already running: $INSTANCE_ID"
        fi

    else
        if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then
            echo "Deleting Instance: roboshop-$instance"
            aws ec2 terminate-instances --instance-ids $INSTANCE_ID
        else
            echo "roboshop-$instance is not running"
        fi
    fi
done
