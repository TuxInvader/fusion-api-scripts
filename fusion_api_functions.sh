#!/bin/bash

# You need to export the following vars
#
# export fusion_user="user"
# export fusion_pass="password"
# export fusion_api="https://controlplane.haproxy.local/v1"

getClusters() {
    default_jq_fields='{ id: .id, namespace: .namespace, name: .name }'
    action_path="/clusters"

    __parse_read_args $*
    __do_fusion_get

}

getControllerConfig() {
    default_jq_fields='{ schema: .schema, address: .address, port: .port, name: .name }'
    action_path="/controller/configuration"

    __parse_read_args $*
    __do_fusion_get

}

getAwsAutoscaleGroups() {
    default_jq_fields='{ id: .id, cluster_id: .cluster_id, region: .region }'
    action_path="/integrations/aws/stacks"
    
    __parse_read_args $*
    __do_fusion_get

}

createAwsAutoscaleGroup() {
    action_path="/integrations/aws/stacks"
    __parse_write_args $*

    asg_body="{\"ami\": \"$fusion_aws_ami\",\"authentication\":{\"role_arn\": \"$fusion_aws_role\",\"strategy\": \"imds\"},\
            \"capacity\": $fusion_asg_capacity,\"cluster_id\": \"$fusion_cluster_id\",\"instance_type\": \"$fusion_aws_hw_type\",\"key_name\": \"$fusion_aws_sshkey\", \
            \"region\": \"$fusion_aws_region\",\"security_groups\": [ \"$fusion_aws_secgroup\" ], \"subnets\": [ \"$fusion_aws_subnet\" ], \
            \"use_public_ipv4\": false }"

    checkArgs fusion_aws_ami fusion_aws_role fusion_asg_capacity fusion_cluster_id fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroup fusion_aws_subnet
    if [ "$?" -eq 0 ]
    then
        __fetch_api "${action_path}" 'POST' "${asg_body}"
        echo "${fusion_response}" | jq
    fi
    __reset_args
}

deleteAwsAutoscaleGroup() {
    __parse_write_args $*
    action_path="/integrations/aws/stacks/${fusion_asg_id}"
    checkArgs fusion_asg_id
    if [ "$?" -eq 0 ]
    then
        __fetch_api "${action_path}" 'DELETE'
        echo "${fusion_response}" | jq
    fi
}

createBootstrapKey() {
    __parse_write_args $*
    action_path="/clusters/${fusion_cluster_id}/bootstrap"
    checkArgs fusion_cluster_id
    if [ "$?" -eq 0 ]
    then
        body="{}"
        __fetch_api "${action_path}" 'POST' "$body"
        echo "${fusion_response}" | jq
        unset exp_date
    fi
    __reset_args
}

checkArgs() {
    args=( $@ )
    unset missing
    for (( i=0; $i < $# ; i++ ))
    do
        if [[ -z "${!args[$i]+x}" ]]
        then
            nextarg=$(echo "${args[$i]}" | sed -re 's/(^|fusion_)/--/g' | sed -re s'/_/-/g')
            [ -z "${missing+x}" ] && missing="$nextarg" || missing="${missing} ${nextarg}"
            unset nextarg
        fi
    done
    if [ -n "${missing}" ]
    then
        echo "You need to supply the following arguments: ${missing}" >&2
        return 1
    fi
}

__do_fusion_get() {
    __fetch_api ${action_path}
    __build_jq_filter
    if [ "${arg_raw}" == true ]
    then
        echo "$fusion_response"
    else
        echo "$fusion_response" | $jq_cmd "${jq_filter}"
    fi
    __reset_args
}

__fetch_api() {
    path=$1
    if [ "$#" == 1 ]
    then
        method="GET"
    else 
        method=$2
    fi
    fusion_response=""
    [ -n "${arg_debug+x}" ] && echo "DEBUG: API-Base: ${fusion_api}, Path: ${path}, Method: ${method}" >&2
    if [ "$method" == "POST" ] || [ "$method" == "PUT" ]
    then
        body=$3
        if [ -n "${arg_debug+x}" ]
        then
            echo "DEBUG: Body: ${body}" >&2
            fusion_response=$(curl -sv --user "${fusion_user}:${fusion_pass}" -H "Content-Type: application/json" -X "$method" -d "$body" "${fusion_api}${path}")
        else
            fusion_response=$(curl -s --user "${fusion_user}:${fusion_pass}" -H "Content-Type: application/json" -X "$method" -d "$body" "${fusion_api}${path}")
        fi
    else
        if [ -n "${arg_debug+x}" ]
        then
            fusion_response=$(curl -sv --user "${fusion_user}:${fusion_pass}" -X "$method" "${fusion_api}${path}")
        else
            fusion_response=$(curl -s --user "${fusion_user}:${fusion_pass}" -X "$method" "${fusion_api}${path}")
        fi
    fi
}

__build_jq_filter() {

    type="hash"
    $(echo "${fusion_response[0]}" | egrep "^\[" >/dev/null) && type="array"

    unset jq_filter

    if [ "$type" == "hash" ]
    then
        jq_filter=" . "
    else
        if [ "${arg_shell}" == true ]
        then
            jq_filter=" .[] "
        else
            jq_filter="[ .[] "
        fi
    fi

    if [ -n "$arg_select" ]
    then
        jq_filter="${jq_filter} | select( ${arg_select} ) "
    fi

    if [ -n "$arg_fields" ]
    then
        IFS=, read -ra FIELDS <<< "${arg_fields}"
        if [ "${arg_shell}" == true ]
        then
            jq_filter="${jq_filter} | .${FIELDS[0]}"
        else
            jq_filter="${jq_filter} | {"
            for f in "${FIELDS[@]}"
            do
                fn=$(echo "$f" | sed -re 's/\./__/g')
                jq_filter="${jq_filter} $fn: .$f,"
            done
            jq_filter="${jq_filter} }"
        fi
    elif [ -z "${arg_all}" ]
    then
        jq_filter="${jq_filter} | ${default_jq_fields} "
    fi

    [ "${arg_shell}" != true ] && [ "$type" != "hash" ] && jq_filter="${jq_filter} ]"
    [ -n "${arg_debug+x}" ] && [ -z "${arg_raw+x}" ] && echo "DEBUG: JQ_command: ${jq_cmd} '${jq_filter}'" >&2
}

__reset_args() {
    unset fusion_asg_capacity fusion_asg_id fusion_cluster_id fusion_bootstrap_duration 
    unset fusion_aws_ami fusion_aws_role  fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroup fusion_aws_subnet
    unset arg_fields arg_select arg_raw arg_all arg_shell arg_debug
    unset jq_cmd fusion_response jq_filter
}

__parse_write_args() {
    args=( $@ )
    unset fusion_aws_ami fusion_aws_role fusion_asg_capacity fusion_cluster_id fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroup fusion_aws_subnet
    unset fusion_bootstrap_duration
    jq_cmd="jq"
    for (( i=0; $i < $# ; i++ ))
    do
        [[ "${args[$i]}" =~ --cluster-id.* ]] && fusion_cluster_id=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --bootstrap-duration.* ]] && fusion_bootstrap_duration=${args[$i]#*=} && continue

        [[ "${args[$i]}" =~ --asg-capacity.* ]] && fusion_asg_capacity=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --asg-id.* ]] && fusion_asg_id=${args[$i]#*=} && continue

        [[ "${args[$i]}" =~ --aws-ami.* ]] && fusion_aws_ami=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-role.* ]] && fusion_aws_role=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-hw-type.* ]] && fusion_aws_hw_type=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-sshkey.* ]] && fusion_aws_sshkey=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-region.* ]] && fusion_aws_region=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-secgroup.* ]] && fusion_aws_secgroup=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-subnet.* ]] && fusion_aws_subnet=${args[$i]#*=} && continue

        [[ "${args[$i]}" =~ --debug ]] && arg_debug=true && continue
    done
}

__parse_read_args() {
    args=( $@ )
    unset arg_fields arg_select arg_raw arg_all arg_shell
    for (( i=0; $i < $# ; i++ ))
    do
        [[ "${args[$i]}" =~ --fields.* ]] && arg_fields=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --id.* ]] && arg_select=" .id == \"${args[$i]#*=}\" " && continue
        [[ "${args[$i]}" =~ --name.* ]] && arg_select=" .name == \"${args[$i]#*=}\" " && continue
        [[ "${args[$i]}" =~ --select.* ]] && arg_select=$(echo "${args[$i]#*=}" | sed -re 's/(.*)[=:](.*)/\.\1 == "\2\"/') && continue
        [[ "${args[$i]}" =~ --raw ]] && arg_raw=true && continue
        [[ "${args[$i]}" =~ --all ]] && arg_all=true && continue
        [[ "${args[$i]}" =~ --shell ]] && arg_shell=true && continue
        [[ "${args[$i]}" =~ --debug ]] && arg_debug=true && continue
    done
    if [ $arg_shell ]
    then
        jq_cmd="jq -cMr"
    else
        jq_cmd="jq"
    fi
}

