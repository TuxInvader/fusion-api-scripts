#!/bin/bash

source fusion_api_functions.sh

args=( $@ )
for (( i=0; $i < $# ; i++ ))
do
    [[ "${args[$i]}" =~ --cluster_name.* ]] && cluster_name=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --duration.* ]] && duration=${args[$i]#*=} && continue
done

checkArgs cluster_name
[ "$?" -ne 0 ] && exit 1
[ -z "${duration+x}" ] && duration=3600

cluster_id=$(getClusters --name="${cluster_name} --fields=id --shell")
createBootstrapKey --cluster-id="${cluster_id}" --bootstrap-duration="${duration}" --debug
