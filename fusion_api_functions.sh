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

getHaproxyNodes() {
    default_jq_fields='{ id: .id, name: .name, description: .description, cluster_id: .cluster_id }'
    action_path="/nodes"

    __parse_read_args $*
    __do_fusion_get
}

getClusterLogTargets() {
    default_jq_fields='{ id: .id, name: .name, log_type: .log_type }'
    action_path="/controller/addons/cluster_log_targets"

    __parse_read_args $*
    __do_fusion_get
}

getOther() {
    default_jq_fields='.'
    __parse_read_args $*
    action_path="/${arg_other_action}"
    __do_fusion_get

}

createClusterLogTarget() {
    action_path="/controller/addons/cluster_log_targets"
    __parse_write_args $*

    [ -z "${fusion_enabled+x}" ] && fusion_enabled=true
    [ -z "${fusion_log_fusion+x}" ] && fusion_log_fusion=false
    [ -z "${fusion_log_haproxy+x}" ] && fusion_log_haproxy=true
    [ -z "${fusion_transport+x}" ] && fusion_transport="TCP"
    
    logtarget_body="{\"enabled\": ${fusion_enabled}, \"log_type\": { \"fusion\": ${fusion_log_fusion}, \"haproxy\": ${fusion_log_haproxy} }, \
                \"name\": \"${fusion_name}\", \"target_ip\": \"${fusion_ip_address}\", \"target_port\": ${fusion_port}, \
                \"transport\": \"${fusion_transport}\"}"

    checkArgs fusion_name fusion_ip_address fusion_port
    if [ "$?" -eq 0 ]
    then
        __fetch_api "${action_path}" 'POST' "${logtarget_body}"
        echo "${fusion_response}" | jq
    fi
    unset logtarget_body
    __reset_args
}

createAwsAutoscaleGroup() {
    action_path="/integrations/aws/stacks"
    __parse_write_args $*

    fusion_aws_secgroups=$(echo "$fusion_aws_secgroups" | sed -re 's/(^\"*|\"*$)/"/g;s/\"*,\"*/\",\"/g' )
    fusion_aws_subnets=$(echo "$fusion_aws_subnets" | sed -re 's/(^\"*|\"*$)/"/g;s/\"*,\"*/\",\"/g' )

    asg_body="{\"ami\": \"$fusion_aws_ami\",\"authentication\":{\"role_arn\": \"$fusion_aws_role\",\"strategy\": \"imds\"},\
            \"capacity\": $fusion_asg_capacity,\"cluster_id\": \"$fusion_cluster_id\",\"instance_type\": \"$fusion_aws_hw_type\",\"key_name\": \"$fusion_aws_sshkey\", \
            \"region\": \"$fusion_aws_region\",\"security_groups\": [ $fusion_aws_secgroups ], \"subnets\": [ $fusion_aws_subnets ], \
            \"use_public_ipv4\": false }"

    checkArgs fusion_aws_ami fusion_aws_role fusion_asg_capacity fusion_cluster_id fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroups fusion_aws_subnets
    if [ "$?" -eq 0 ]
    then
        __fetch_api "${action_path}" 'POST' "${asg_body}"
        echo "${fusion_response}" | jq
    fi
    unset asg_body
    __reset_args
}

deleteHaproxyNode() {
   __parse_write_args $*
    action_path="/nodes/${fusion_node_id}"
    checkArgs fusion_node_id
    if [ "$?" -eq 0 ]
    then
        __fetch_api "${action_path}" 'DELETE'
        echo "${fusion_response}" | jq
    fi
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
            nextarg=$(echo "${args[$i]}" | sed -re 's/(^|fusion_)/--/g; s/_/-/g')
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
    unset fusion_asg_capacity fusion_asg_id
    unset fusion_aws_ami fusion_aws_role  fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroups fusion_aws_subnets
    unset fusion_cluster_id fusion_node_id fusion_other_action
    unset arg_fields arg_select arg_raw arg_all arg_shell arg_debug arg_other_action
    unset jq_cmd fusion_response jq_filter action_path default_jq_fields
    unset fusion_enabled fusion_name fusion_ip_address fusion_port fusion_transport 
    unset fusion_log_haproxy fusion_log_fusion
}

__parse_write_args() {
    args=( $@ )
    unset fusion_aws_ami fusion_aws_role fusion_cluster_id fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroups fusion_aws_subnets
    unset fusion_asg_capacity fusion_asg_id 
    unset fusion_cluster_id fusion_node_id
    unset fusion_enabled fusion_name fusion_ip_address fusion_port fusion_transport 
    unset fusion_log_haproxy fusion_log_fusion

    jq_cmd="jq"
    for (( i=0; $i < $# ; i++ ))
    do
        # Generic, used for multiple APIs
        [[ "${args[$i]}" =~ --name.* ]] && fusion_name=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --enabled.* ]] && fusion_enabled=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --ip-address.* ]] && fusion_ip_address=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --port.* ]] && fusion_port=${args[$i]#*=} && continue
        # log targets
        [[ "${args[$i]}" =~ --log-haproxy.* ]] && fusion_log_haproxy=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --log-fusion.* ]] && fusion_log_fusion=${args[$i]#*=} && continue
        # cluster related
        [[ "${args[$i]}" =~ --cluster-id.* ]] && fusion_cluster_id=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --node-id.* ]] && fusion_node_id=${args[$i]#*=} && continue
        # asg related
        [[ "${args[$i]}" =~ --asg-capacity.* ]] && fusion_asg_capacity=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --asg-id.* ]] && fusion_asg_id=${args[$i]#*=} && continue
        # aws related
        [[ "${args[$i]}" =~ --aws-ami.* ]] && fusion_aws_ami=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-role.* ]] && fusion_aws_role=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-hw-type.* ]] && fusion_aws_hw_type=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-sshkey.* ]] && fusion_aws_sshkey=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-region.* ]] && fusion_aws_region=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-secgroups.* ]] && fusion_aws_secgroups=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --aws-subnets.* ]] && fusion_aws_subnets=${args[$i]#*=} && continue

        [[ "${args[$i]}" =~ --debug ]] && arg_debug=true && continue
    done
}

__parse_read_args() {
    args=( $@ )
    unset arg_fields arg_select arg_raw arg_all arg_shell arg_debug arg_other_action
    for (( i=0; $i < $# ; i++ ))
    do
        [[ "${args[$i]}" =~ --fields.* ]] && arg_fields=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --id.* ]] && arg_select=" .id == \"${args[$i]#*=}\" " && continue
        [[ "${args[$i]}" =~ --name.* ]] && arg_select=" .name == \"${args[$i]#*=}\" " && continue
        [[ "${args[$i]}" =~ --select.* ]] && arg_select=$(echo "${args[$i]#*=}" | sed -re 's/(.*)[=:](.*)/\.\1 == "\2\"/') && continue
        [[ "${args[$i]}" =~ --other-action.* ]] && arg_other_action=${args[$i]#*=} && continue
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

