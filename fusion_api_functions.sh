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
    __build_jq_filter

    if [ "${arg_raw}" == true ]
    then
        __fetch_api ${action_path}
    else
        [ -n "${arg_debug+x}" ] && echo "Path: $action_path, JQ: $jq_cmd $jq_args" >&2
        __fetch_api ${action_path} | $jq_cmd "${jq_args}"
    fi
    __reset_args
}

getAwsAutoscaleGroups() {
    default_jq_fields='{ id: .id, cluster_id: .cluster_id, region: .region }'
    action_path="/integrations/aws/stacks"
    
    __parse_read_args $*
    __build_jq_filter

    if [ "${arg_raw}" == true ]
    then
        __fetch_api ${action_path}
    else
        [ -n "${arg_debug+x}" ] && echo "Path: $action_path, JQ: $jq_cmd $jq_args" >&2
        __fetch_api ${action_path} | $jq_cmd "${jq_args}"
    fi
    __reset_args
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
        [ -n "${arg_debug+x}" ] && echo "Path: $action_path, body: ${body}" >&2
        __fetch_api "${action_path}" 'POST' "${asg_body}" | jq
    fi
    __reset_args
}

createBootstrapKey() {
    __parse_write_args $*
    action_path="/clusters/${fusion_cluster_id}/bootstrap"
    checkArgs fusion_cluster_id fusion_bootstrap_duration
    if [ "$?" -eq 0 ]
    then
        body="{\"bootstrap_key_duration\": ${fusion_bootstrap_duration}}"
        [ -n "${arg_debug+x}" ] && echo "Path: $action_path, body: ${body}" >&2
        __fetch_api "${action_path}" 'POST' "$body" | jq
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

__fetch_api() {
    path=$1
    method=$2
    response=""
    if [ "$method" == "POST" ] || [ "$method" == "PUT" ]
    then
        body=$3
        response=$(curl -s --user "${fusion_user}:${fusion_pass}" -H "Content-Type: application/json" -X "$method" -d "$body" "${fusion_api}${path}")
    else
        response=$(curl -s --user "${fusion_user}:${fusion_pass}" "${fusion_api}${path}")
    fi
    echo $response
}

__build_jq_filter() {
    unset jq_args

    if [ "${arg_shell}" == true ]
    then
        jq_args=" .[] "
    else
        jq_args="[ .[] "
    fi

    if [ -n "$arg_select" ]
    then
        jq_args="${jq_args} | select( ${arg_select} ) "
    fi

    if [ -n "$arg_fields" ]
    then
        IFS=, read -ra FIELDS <<< "${arg_fields}"
        if [ "${arg_shell}" == true ]
        then
            jq_args="${jq_args} | .${FIELDS[0]}"
        else
            jq_args="${jq_args} | {"
            for f in "${FIELDS[@]}"
            do
                fn=$(echo "$f" | sed -re 's/\./__/g')
                jq_args="${jq_args} $fn: .$f,"
            done
            jq_args="${jq_args} }"
        fi
    elif [ -z "${arg_all}" ]
    then
        jq_args="${jq_args} | ${default_jq_fields} "
    fi

    [ "${arg_shell}" != true ] && jq_args="${jq_args} ]"
}

__reset_args() {
    unset fusion_asg_capacity fusion_cluster_id fusion_bootstrap_duration
    unset fusion_aws_ami fusion_aws_role  fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroup fusion_aws_subnet
    unset arg_fields arg_select arg_raw arg_all arg_shell arg_debug
    unset jq_cmd
}

__parse_write_args() {
    args=( $@ )
    unset fusion_aws_ami fusion_aws_role fusion_asg_capacity fusion_cluster_id fusion_aws_hw_type fusion_aws_sshkey fusion_aws_region fusion_aws_secgroup fusion_aws_subnet
    unset fusion_bootstrap_duration
    for (( i=0; $i < $# ; i++ ))
    do
        [[ "${args[$i]}" =~ --cluster-id.* ]] && fusion_cluster_id=${args[$i]#*=} && continue
        [[ "${args[$i]}" =~ --bootstrap-duration.* ]] && fusion_bootstrap_duration=${args[$i]#*=} && continue

        [[ "${args[$i]}" =~ --asg-capacity.* ]] && fusion_asg_capacity=${args[$i]#*=} && continue

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

