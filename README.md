# Fusion API Shell functions

This is just a bunch of bash scripts for interacting the with Fusion API.

The main functions are in `fusion_api_functions.sh` and can be loaded into other scripts via sourcing
```
source fusion_api_functions
```

A simple example
```
#!/bin/bash

source fusion_api_functions.sh
getAwsAutoscaleGroups $*
```

All functions require you to have the following environment variables set
```
export fusion_user="user"
export fusion_pass="password"
export fusion_api="https://controlplane.haproxy.local/v1"
```

## READ Operations

Read operations such as `getClusters` take the following additional options

| Parameter | Example | Description |
|-----------|-------------|---------|
| --select  | --select=name:default | Select resources with matching key/value pairs|
| --name    | --name=default        | Select shortcut to match on the resource name |
| --id      | --id={uuid}           | Select shortcut to match on the resource ID   |
| --fields  | --fields=id,name      | limits the fields return to only those specified |
| --all     | --all                 | Returns all fields returned from the API |
| --shell   | --fields=id --shell   | Use with `--fields`  to returns a single item and unwrap from JSON |
| --debug   | --debug               | Print information about the endpoint and the JQ params used |
| --raw     | --raw                 | Do not pass the response through jq |


### Some more Examples

Get the cluster id of the "New Delhi" cluster and return it as a single value
```
getClusters --select=name:newdelhi --fields=id --shell
```

Get all information about the "default" cluster.
```
getClusters --select=name:default --all
```

Get all clusters and return their name,id and the nested timestamp from resources_version
```
getClusters --fields=name,id,resources_version.timestamp
```

Nested resources are flattened with `__` delimiters. The above example would return the key `resources_version__timestamp`.

