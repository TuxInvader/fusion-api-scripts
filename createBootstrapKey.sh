#!/bin/bash

source fusion_api_functions.sh

args=( $@ )
for (( i=0; $i < $# ; i++ ))
do
    [[ "${args[$i]}" =~ --cluster_name.* ]] && cluster_name=${args[$i]#*=} && continue
done

checkArgs cluster_name
[ "$?" -ne 0 ] && exit 1

cluster_id=$(getClusters --name="${cluster_name} --fields=id --shell")
createBootstrapKey --cluster-id="${cluster_id}"
