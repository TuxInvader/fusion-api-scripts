#!/bin/bash

source fusion_api_functions.sh

args=( $@ )
for (( i=0; $i < $# ; i++ ))
do
    [[ "${args[$i]}" =~ --cluster-name.* ]] && cluster_name=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --aws-region.* ]] && aws_region=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --aws-role.* ]] && aws_role=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --aws-secgroup-name.* ]] && aws_secgroup_name=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --aws-subnet-name.* ]] && aws_subnet_name=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --aws-sshkey.* ]] && aws_sshkey=${args[$i]#*=} && continue
    # optional
    [[ "${args[$i]}" =~ --aws-inst-type.* ]] && aws_inst_type=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --hapee-os.* ]] && hapee_os=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --hapee-version.* ]] && hapee_version=${args[$i]#*=} && continue
done

checkArgs cluster_name aws_region aws_role aws_secgroup_name aws_subnet_name aws_sshkey
[ "$?" -ne 0 ] && exit 1
[ -z "${aws_inst_type+x}" ] && aws_inst_type="t2.small"
[ -z "${hapee_version+x}" ] && hapee_version="2.8r1"
[ -z "${hapee_os+x}" ] && hapee_os="ubuntu-jammy"

hapee_image=$(aws --region "${aws_region}" ec2   describe-images --filters "Name=name,Values=hapee-${hapee_os}-amd64*${hapee_version}*" | jq -cMr ".Images[0].ImageId")
aws_asg_role=$(aws iam get-role --role-name "${aws_role}" | jq -cMr ".Role.Arn")
aws_sg_ids=$(aws --region "${aws_region}" ec2 describe-security-groups --filters "Name=tag:Name,Values=${aws_secgroup_name}" | jq -cMr ".SecurityGroups[].GroupId")
aws_subnet_ids=$(aws --region "${aws_region}" ec2 describe-subnets --filters "Name=tag:Name,Values=${aws_subnet_name}" | jq -cMr ".Subnets[].SubnetId")
cluster_id=$(getClusters --name="${cluster_name} --fields=id --shell")

cat <<EOF 
AWS Region  ....................  ${aws_region}
AWS Role Id:  ..................  ${aws_asg_role}
AWS Instance Type:  ............  ${aws_inst_type}
AWS KeyPair ....................  ${aws_sshkey}
AWS SecurityGroup Ids:  ........  $( echo ${aws_sg_ids[@]} )
AWS Subnet Ids  ................  $( echo ${aws_subnet_ids[@]} )
HAPEE Image Id:  ...............  ${hapee_image}

Fusion_Cluster:
  Name .........................  ${cluster_name}
  ID   .........................  ${cluster_id}

EOF

read -p "Proceed (y/n)?  $ " proc

if [ "$proc" != "y" ]
then
    echo "Aborting"
    exit 1
fi

createAwsAutoscaleGroup --aws-ami="$hapee_image" --aws-role="${aws_asg_role}" --asg-capacity="2" --cluster-id="${cluster_id}" \
                        --aws-hw-type="${aws_inst_type}" --aws-sshkey="${aws_sshkey}" --aws-region="${aws_region}" \
                        --aws-secgroup="${aws_sg_ids[@]}" --aws-subnet="${aws_subnet_ids[@]}"
