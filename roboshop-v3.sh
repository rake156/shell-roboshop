
#!/bin/bash

AWS_REGION="us-east-1"
AMI_ID="ami-0eec78ea4cbaaf5bd"
ZONE_ID="Z0702543JR335XUHBX9I"
DOMAIN_NAME="rakesh08.online"

R="\e[31m"
G="\e[32m"
Y="\e[33m"
N="\e[0m"

ALL_INSTANCES="mongodb redis mysql rabbitmq catalogue user cart shipping payment frontend"

### Validation ###
if [ $# -lt 2 ]; then
    echo -e "${R}ERROR:: At least 2 arguments required${N}"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

ACTION="$1"
shift

if [ "$ACTION" != "create" ] && [ "$ACTION" != "delete" ]; then
    echo -e "${R}ERROR:: First argument must be create or delete${N}"
    echo "USAGE: $0 [create/delete] [instance1] [instance2...]"
    exit 1
fi

### Select instances ###
if [ "$1" = "all" ]; then
    if [ "$ACTION" = "create" ]; then
        INSTANCES="$ALL_INSTANCES"
    else
        INSTANCES=$(echo "$ALL_INSTANCES" | tr ' ' '\n' | tac | tr '\n' ' ')
    fi
else
    INSTANCES="$*"
fi

### Find an existing instance ###
get_instance_id() {
    local name="$1"

    aws ec2 describe-instances \
        --region "$AWS_REGION" \
        --filters "Name=tag:Name,Values=roboshop-$name" \
                  "Name=instance-state-name,Values=running,pending,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId" \
        --output text 2>/dev/null |
        awk '{print $1}'
}

### Process instances ###
for instance in $INSTANCES; do

    INSTANCE_ID=$(get_instance_id "$instance")

    if [ "$ACTION" = "create" ]; then

        if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
            echo "roboshop-$instance already exists: $INSTANCE_ID"
            echo "Skipping creation to avoid duplicates."
            continue
        fi

        echo "Launching Instance: roboshop-$instance"

        INSTANCE_ID=$(aws ec2 run-instances \
            --region "$AWS_REGION" \
            --image-id "$AMI_ID" \
            --instance-type t3.micro \
            --security-groups "roboshop-common" "roboshop-$instance" \
            --tag-specifications \
                "ResourceType=instance,Tags=[{Key=Name,Value=roboshop-$instance}]" \
            --query 'Instances[0].InstanceId' \
            --output text) || {
                echo "ERROR: Failed to launch roboshop-$instance"
                continue
            }

        if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
            echo "ERROR: No instance ID returned for roboshop-$instance"
            continue
        fi

        echo "Launched Instance: $INSTANCE_ID"

        if ! aws ec2 wait instance-running \
            --region "$AWS_REGION" \
            --instance-ids "$INSTANCE_ID"; then
            echo "ERROR: Instance did not reach running state: $INSTANCE_ID"
            echo "Check its state in the EC2 Console before retrying."
            continue
        fi

        if [ "$instance" = "frontend" ]; then
            IP=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PublicIpAddress' \
                --output text)

            R53_RECORD="$DOMAIN_NAME"
        else
            IP=$(aws ec2 describe-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID" \
                --query 'Reservations[0].Instances[0].PrivateIpAddress' \
                --output text)

            R53_RECORD="$instance.$DOMAIN_NAME"
        fi

        if [ -z "$IP" ] || [ "$IP" = "None" ]; then
            echo "ERROR: Could not get IP for roboshop-$instance"
            echo "Instance remains running; check its network configuration."
            continue
        fi

        echo "Updating Route 53: $R53_RECORD -> $IP"

        if aws route53 change-resource-record-sets \
            --hosted-zone-id "$ZONE_ID" \
            --change-batch "{
                \"Comment\": \"Update A record to new IP\",
                \"Changes\": [{
                    \"Action\": \"UPSERT\",
                    \"ResourceRecordSet\": {
                        \"Name\": \"$R53_RECORD\",
                        \"Type\": \"A\",
                        \"TTL\": 60,
                        \"ResourceRecords\": [{
                            \"Value\": \"$IP\"
                        }]
                    }
                }]
            }"; then
            echo "Route 53 updated: $R53_RECORD -> $IP"
        else
            echo "ERROR: Route 53 update failed for $R53_RECORD"
        fi

    elif [ "$ACTION" = "delete" ]; then

        if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
            echo "Terminating roboshop-$instance: $INSTANCE_ID"

            if aws ec2 terminate-instances \
                --region "$AWS_REGION" \
                --instance-ids "$INSTANCE_ID"; then
                echo "Termination requested for roboshop-$instance"
                echo "Route 53 record preserved."
            else
                echo "ERROR: Failed to terminate roboshop-$instance"
            fi
        else
            echo "No matching active instance found for roboshop-$instance"
            echo "No changes made."
        fi
    fi
done
