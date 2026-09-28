package main

deny contains msg if {
    some resource in input.resource_changes

    resource.type == "aws_security_group"

    some ingress in resource.change.after.ingress

    ingress.from_port == 22
    ingress.to_port == 22

    "0.0.0.0/0" in ingress.cidr_blocks

    msg := sprintf(
        "Security violation: %s exposes SSH port 22 to 0.0.0.0/0",
        [resource.address]
    )
}
