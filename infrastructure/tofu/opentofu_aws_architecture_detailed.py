"""
Detailliertes SVG-Architekturdiagramm fuer die OpenTofu-Infrastruktur.

Ausfuehren (aus infrastructure/tofu):
  python3 opentofu_aws_architecture_detailed.py
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.database import RDS
from diagrams.aws.management import Cloudwatch
from diagrams.aws.network import InternetGateway, PublicSubnet, RouteTable, VPC
from diagrams.aws.security import IAM
from diagrams.aws.storage import S3
from diagrams.generic.client import Users


GRAPH_ATTR = {
    "fontsize": "20",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "spline",
}


with Diagram(
    "GroceryMate OpenTofu AWS Architecture (Detailed)",
    filename="opentofu_aws_architecture_detailed",
    show=False,
    direction="LR",
    outformat="svg",
    graph_attr=GRAPH_ATTR,
):
    users = Users("Web Clients")
    igw = InternetGateway("Internet Gateway")

    with Cluster("AWS Account / Region eu-central-1"):
        with Cluster("Default VPC"):
            subnet = PublicSubnet("Default Subnets")
            routes = RouteTable("Route Table")
            ec2 = EC2("EC2 grocery-ec2\nNginx + Docker + Flask Backend")
            rds = RDS("RDS PostgreSQL\nPort 5432")

        s3 = S3("S3 Bucket\navatars/*")
        iam = IAM("IAM Role + Instance Profile\n(grocery-ec2-role)")
        cw = Cloudwatch("CloudWatch Log Group\n/grocerymate/ec2/backend")

    users >> Edge(label="HTTP :80\n/api/* via Nginx") >> igw >> ec2
    subnet >> routes >> ec2
    ec2 >> Edge(label="DB traffic :5432") >> rds
    ec2 >> Edge(label="Get/Put avatars") >> s3
    ec2 >> Edge(label="awslogs driver") >> cw
    iam >> Edge(label="AssumeRole + permissions") >> ec2
