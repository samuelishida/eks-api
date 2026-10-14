# Tracked reference tfvars for dev (exception in .gitignore).
# The runbook bootstraps the state bucket/lock table and substitutes the
# real account ID into `backend_bucket` before the first `terraform init`.

region              = "us-east-1"
env_name            = "dev"
vpc_cidr            = "10.10.0.0/16"
azs                 = ["us-east-1a", "us-east-1b", "us-east-1c"]
node_instance_types = ["t3.small"]
asg_min             = 1
asg_max             = 3
asg_desired         = 1

# State backend (bootstrapped by the runbook; the runbook substitutes the
# real account ID into the bucket name).
backend_bucket = "eks-api-tfstate"
lock_table     = "eks-api-tflock"
