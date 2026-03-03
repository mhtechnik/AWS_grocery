"""
Erzeugt ein Architekturdiagramm fuer die OpenTofu-Infrastruktur von GroceryMate.

Voraussetzungen:
- python3 -m pip install diagrams
- graphviz (Systempaket), z. B. sudo apt-get install -y graphviz

Ausfuehren (aus infrastructure/tofu):
  python3 opentofu_architecture_diagram.py
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import InternetGateway, PublicSubnet, VPC
from diagrams.aws.security import IAM
from diagrams.aws.storage import S3
from diagrams.generic.device import Mobile


GRAPH_ATTR = {
    "fontsize": "18",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "spline",
}


with Diagram(
    "GroceryMate OpenTofu AWS Architecture",
    filename="opentofu_aws_architecture",
    show=False,
    direction="LR",
    graph_attr=GRAPH_ATTR,
):
    users = Mobile("Nutzer")
    internet = InternetGateway("Internet")

    with Cluster("AWS Account (eu-central-1)"):
        with Cluster("Default VPC"):
            subnet = PublicSubnet("Default Subnets")
            ec2 = EC2("EC2 grocery-ec2\nDocker + Nginx + Backend")
            rds = RDS("RDS PostgreSQL\ngrocerymate-db")

        s3 = S3("S3 Avatar Bucket\n(grocerymate-avatars-...)")
        iam = IAM("IAM Role + Instance Profile\n(grocery-ec2-role)")
        cloudwatch = Cloudwatch("CloudWatch Logs\n/grocerymate/ec2/backend")

    users >> internet >> ec2
    subnet >> ec2
    ec2 >> Edge(label="Port 5432") >> rds
    ec2 >> Edge(label="avatars/*") >> s3
    ec2 >> Edge(label="container logs") >> cloudwatch
    iam >> Edge(label="attached to EC2") >> ec2

