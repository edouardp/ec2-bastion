#!/usr/bin/env python3
"""Emit Make-compatible KEY=VALUE lines from a YAML config file."""
import sys
import yaml

with open(sys.argv[1]) as f:
    for k, v in yaml.safe_load(f).items():
        print(f"{k.upper()}={v}")
