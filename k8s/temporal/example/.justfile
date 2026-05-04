# Hello-world Temporal workflow against the cluster.
# Defaults connect to temporal.5xx.engineer:443 with ~/.temporal/laptop/* certs.

# Start a worker, run GreetingWorkflow once, then exit
run NAME="world":
    go run . "{{NAME}}"

# Open the workflow list in the Web UI
ui:
    open https://temporal-ui.5xx.engineer/namespaces/default/workflows
