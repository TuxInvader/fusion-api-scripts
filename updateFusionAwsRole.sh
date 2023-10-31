#!/bin/bash

source fusion_api_functions.sh

args=( $@ )
for (( i=0; $i < $# ; i++ ))
do
    [[ "${args[$i]}" =~ --old-role.* ]] && fusion_old_role=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --new-role.* ]] && fusion_new_role=${args[$i]#*=} && continue
    [[ "${args[$i]}" =~ --profile.* ]] && fusion_profile=${args[$i]#*=} && continue
done

checkArgs fusion_old_role fusion_new_role fusion_profile
[ "$?" -ne 0 ] && exit 1

aws iam remove-role-from-instance-profile --instance-profile-name "$fusion_profile" --role-name "$fusion_old_role"
aws iam add-role-to-instance-profile --instance-profile-name "$fusion_profile" --role-name "$fusion_new_role"
