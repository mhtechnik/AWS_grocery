"""
Automatischer Diagramm-Generator fuer OpenTofu-Strukturen.

Der Generator liest alle *.tf-Dateien in diesem Ordner, erkennt resource/data-
Bloecke sowie Referenzen und rendert daraus ein AWS-Architekturdiagramm.

Beispiele:
  python3 opentofu_auto_diagram.py
  python3 opentofu_auto_diagram.py --out opentofu_aws_architecture_auto
  python3 opentofu_auto_diagram.py --watch --interval 2
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Set, Tuple

from diagrams import Cluster, Diagram, Edge
from diagrams.generic.blank import Blank
from diagrams.onprem.client import Users
from diagrams.aws.network import InternetGateway, PublicSubnet


BLOCK_RE = re.compile(r'^\s*(resource|data)\s+"([^"]+)"\s+"([^"]+)"\s*{')
REF_RE = re.compile(r"\b(data\.)?[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+")


@dataclass(frozen=True)
class TfBlock:
    kind: str  # resource | data
    tf_type: str
    name: str
    body: str

    @property
    def address(self) -> str:
        prefix = "data" if self.kind == "data" else "resource"
        return f"{prefix}.{self.tf_type}.{self.name}"


ICON_MAP: Dict[str, Tuple[str, str]] = {
    "aws_instance": ("diagrams.aws.compute", "EC2"),
    "aws_db_instance": ("diagrams.aws.database", "RDS"),
    "aws_db_subnet_group": ("diagrams.aws.database", "RDS"),
    "aws_s3_bucket": ("diagrams.aws.storage", "S3"),
    "aws_s3_bucket_public_access_block": ("diagrams.aws.storage", "S3"),
    "aws_s3_bucket_versioning": ("diagrams.aws.storage", "S3"),
    "aws_iam_role": ("diagrams.aws.security", "IAM"),
    "aws_iam_policy": ("diagrams.aws.security", "IAM"),
    "aws_iam_instance_profile": ("diagrams.aws.security", "IAM"),
    "aws_iam_role_policy_attachment": ("diagrams.aws.security", "IAM"),
    "aws_cloudwatch_log_group": ("diagrams.aws.management", "Cloudwatch"),
    "aws_security_group": ("diagrams.onprem.network", "Firewall"),
    "aws_vpc": ("diagrams.aws.network", "VPC"),
    "aws_subnets": ("diagrams.aws.network", "PublicSubnet"),
    "template_file": ("diagrams.onprem.iac", "Terraform"),
}


def load_icon(tf_type: str):
    target = ICON_MAP.get(tf_type)
    if not target:
        return Blank
    module_name, class_name = target
    try:
        module = importlib.import_module(module_name)
        return getattr(module, class_name)
    except Exception:
        return Blank


def category(tf_type: str) -> str:
    if tf_type.startswith("aws_iam"):
        return "IAM"
    if tf_type.startswith("aws_s3"):
        return "Storage"
    if tf_type.startswith("aws_db"):
        return "Database"
    if tf_type.startswith("aws_cloudwatch"):
        return "Observability"
    if tf_type in {"aws_vpc", "aws_subnets", "aws_security_group"}:
        return "Network"
    if tf_type == "aws_instance":
        return "Compute"
    if tf_type.startswith("aws_"):
        return "AWS Other"
    return "Meta/Data"


HIDE_RESOURCE_TYPES: Set[str] = {
    "aws_iam_policy",
    "aws_iam_role_policy_attachment",
    "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_versioning",
}


def parse_blocks(tf_file: Path) -> List[TfBlock]:
    lines = tf_file.read_text(encoding="utf-8").splitlines()
    blocks: List[TfBlock] = []
    i = 0
    while i < len(lines):
        m = BLOCK_RE.match(lines[i])
        if not m:
            i += 1
            continue
        kind, tf_type, name = m.groups()
        depth = lines[i].count("{") - lines[i].count("}")
        body_lines = [lines[i]]
        i += 1
        while i < len(lines) and depth > 0:
            body_lines.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
            i += 1
        blocks.append(TfBlock(kind=kind, tf_type=tf_type, name=name, body="\n".join(body_lines)))
    return blocks


def normalize_ref(token: str) -> str | None:
    parts = token.split(".")
    if parts[0] in {"var", "local", "path", "module"}:
        return None
    if parts[0] == "data" and len(parts) >= 3:
        return f"data.{parts[1]}.{parts[2]}"
    if len(parts) >= 2:
        return f"resource.{parts[0]}.{parts[1]}"
    return None


def extract_edges(blocks: Iterable[TfBlock]) -> Set[Tuple[str, str]]:
    index = {b.address for b in blocks}
    edges: Set[Tuple[str, str]] = set()
    for src in blocks:
        for m in REF_RE.finditer(src.body):
            ref = normalize_ref(m.group(0))
            if ref and ref in index and ref != src.address:
                edges.add((src.address, ref))
    return edges


def build_model(folder: Path) -> Tuple[List[TfBlock], Set[Tuple[str, str]]]:
    tf_files = sorted(p for p in folder.glob("*.tf") if p.name not in {".terraform.lock.hcl"})
    blocks: List[TfBlock] = []
    for tf_file in tf_files:
        blocks.extend(parse_blocks(tf_file))
    return blocks, extract_edges(blocks)


def find_block(blocks: List[TfBlock], kind: str, tf_type: str) -> TfBlock | None:
    for b in blocks:
        if b.kind == kind and b.tf_type == tf_type:
            return b
    return None


def mk_node(block: TfBlock | None, fallback_label: str):
    if block is None:
        return None
    icon = load_icon(block.tf_type)
    # Architekturfreundliche Labels statt Roh-Adressen
    label = fallback_label if fallback_label else f"{block.tf_type}\n{block.name}"
    return icon(label)


def render(
    blocks: List[TfBlock],
    edges: Set[Tuple[str, str]],
    output_name: str,
) -> None:
    _ = edges
    graph_attr = {"fontsize": "18", "bgcolor": "white", "pad": "0.5", "splines": "spline"}

    with Diagram(
        "OpenTofu AWS Architecture (Auto-generated from .tf)",
        filename=output_name,
        show=False,
        direction="LR",
        graph_attr=graph_attr,
        outformat="png",
    ):
        users = Users("Nutzer")
        internet = InternetGateway("Internet")

        ec2_b = find_block(blocks, "resource", "aws_instance")
        rds_b = find_block(blocks, "resource", "aws_db_instance")
        s3_b = find_block(blocks, "resource", "aws_s3_bucket")
        cw_b = find_block(blocks, "resource", "aws_cloudwatch_log_group")
        iam_profile_b = find_block(blocks, "resource", "aws_iam_instance_profile")
        subnets_b = find_block(blocks, "data", "aws_subnets")

        with Cluster("AWS Account"):
            with Cluster("Default VPC"):
                subnet = mk_node(subnets_b, "Default Subnets")
                ec2 = mk_node(ec2_b, "EC2")
                rds = mk_node(rds_b, "RDS PostgreSQL")

            s3 = mk_node(s3_b, "S3 Avatar Bucket")
            cw = mk_node(cw_b, "CloudWatch Logs")
            iam = mk_node(iam_profile_b, "IAM Role + Instance Profile")

        if ec2:
            users >> internet >> ec2
            if subnet:
                subnet >> Edge(label="default network") >> ec2
            if rds:
                ec2 >> Edge(label="Port 5432") >> rds
            if s3:
                ec2 >> Edge(label="avatars/*") >> s3
            if cw:
                ec2 >> Edge(label="container logs") >> cw
            if iam:
                iam >> Edge(label="attached to EC2") >> ec2


def fingerprint(tf_files: Iterable[Path]) -> str:
    h = hashlib.sha256()
    for f in sorted(tf_files):
        h.update(f.name.encode("utf-8"))
        h.update(f.read_bytes())
    return h.hexdigest()


def run_once(folder: Path, output_name: str) -> None:
    blocks, edges = build_model(folder)
    render(blocks, edges, output_name)
    print(f"Diagram generated: {output_name}.png")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="opentofu_aws_architecture_auto", help="Output file name without extension")
    parser.add_argument("--watch", action="store_true", help="Watch *.tf changes and re-render automatically")
    parser.add_argument("--interval", type=float, default=2.0, help="Watch polling interval in seconds")
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent
    tf_files = list(folder.glob("*.tf"))
    run_once(folder, args.out)

    if not args.watch:
        return

    print("Watch mode active. Press Ctrl+C to stop.")
    last = fingerprint(tf_files)
    while True:
        time.sleep(args.interval)
        current_files = list(folder.glob("*.tf"))
        current = fingerprint(current_files)
        if current != last:
            run_once(folder, args.out)
            last = current


if __name__ == "__main__":
    main()
