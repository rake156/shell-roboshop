
#!/bin/bash

AMI_ID="ami-0220d79f3f480ecf5"
ZONE_ID="Z0702543JR335XUHBX9I"
DOMAIN_NAME="rakesh08.online"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "${R}ERROR:: At least 2 arguments required${N}"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

ACTION=$1
shift

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "${R}ERROR:: First argument must be create or delete${N}"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

### Get running instance ID ###
get_instance_id() {
    local name=$1

    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=roboshop-$name" \
                  "Name=instance-state-name,Values=running" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text
}

### Process instances ###
for instance in "$@"
do
    INSTANCE_ID=$(get_instance_id "$instance")

    if [ "$ACTION" = "create" ]; then

        if [ "$INSTANCE_ID" = "None" ] || [ -z "$INSTANCE_ID" ]; then

            echo "Launching Instance: roboshop-$instance"

            INSTANCE_ID=$(aws ec2 run-instances \
                --image-id "$AMI_ID" \
                --instance-type t3.micro \
                --security-groups "roboshop-common" "roboshop-$instance" \
                --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
                --query 'Instances[0].InstanceId' \
                --output text)

            if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
                echo "ERROR: Failed to launch roboshop-$instance"
                continue
            fi

            echo "Launched Instance: $INSTANCE_ID"

            # Wait until the instance is running
            aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

            # Get IP and Route 53 record name
            if [ "$instance" = "frontend" ]; then
                IP=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' \
                    --output text)

                R53_RECORD="$DOMAIN_NAME"
            else
                IP=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                    --output text)

                R53_RECORD="$instance.$DOMAIN_NAME"
            fi

            if [ -z "$IP" ] || [ "$IP" = "None" ]; then
                echo "ERROR: Could not get IP for roboshop-$instance"
                continue
            fi

            # Create or update Route 53 A record
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$ZONE_ID" \
                --change-batch "{
                    \"Comment\": \"Update A record to new IP\",
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

            echo "Route 53 updated: $R53_RECORD -> $IP"

        else
            echo "roboshop-$instance already running: $INSTANCE_ID"
        fi

    elif [ "$ACTION" = "delete" ]; then

        if [ "$INSTANCE_ID" != "None" ] && [ -n "$INSTANCE_ID" ]; then

            echo "Deleting roboshop-$instance: $INSTANCE_ID"

            # Get the IP and matching DNS record
            if [ "$instance" = "frontend" ]; then
                IP=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PublicIpAddress' \
                    --output text)

                R53_RECORD="$DOMAIN_NAME"
            else
                IP=$(aws ec2 describe-instances \
                    --instance-ids "$INSTANCE_ID" \
                    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                    --output text)

                R53_RECORD="$instance.$DOMAIN_NAME"
            fi

            # Remove the Route 53 record if its IP is available
            if [ -n "$IP" ] && [ "$IP" != "None" ]; then
                aws route53 change-resource-record-sets \
                    --hosted-zone-id "$ZONE_ID" \
                    --change-batch "{
                        \"Comment\": \"Delete A record\",
                        \"Changes\": [{
                            \"Action\": \"DELETE\",
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

                echo "Route 53 delete requested for $R53_RECORD"
            fi

            # Terminate the EC2 instance
            aws ec2 terminate-instances \
                --instance-ids "$INSTANCE_ID"

            if [ $? -eq 0 ]; then
                echo "Termination requested for roboshop-$instance"
            else
                echo "ERROR: Failed to terminate roboshop-$instance"
            fi

        else
            echo "roboshop-$instance is not running"
        fi
    fi
done

