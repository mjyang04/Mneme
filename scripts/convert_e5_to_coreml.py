#!/usr/bin/env python3
"""Convert intfloat/multilingual-e5-small into Mneme's local CoreML assets.

Usage:
  uv run --with transformers --with torch --with coremltools \
    scripts/convert_e5_to_coreml.py --output-dir .build/Models/e5

The script writes:
  - multilingual-e5-small.mlpackage
  - e5-tokenizer/tokenizer.json
  - e5-tokenizer/tokenizer_config.json

These files can be copied to:
  ~/Library/Application Support/Mneme/Models/e5/
"""

from __future__ import annotations

import argparse
from pathlib import Path

import coremltools as ct
import torch
from transformers import AutoModel, AutoTokenizer


MODEL_ID = "intfloat/multilingual-e5-small"


class MeanPooledE5(torch.nn.Module):
    def __init__(self, model: torch.nn.Module) -> None:
        super().__init__()
        self.model = model

    def forward(
        self,
        input_ids: torch.Tensor,
        token_type_ids: torch.Tensor,
        position_ids: torch.Tensor,
    ) -> torch.Tensor:
        embeddings = self.model.embeddings(
            input_ids=input_ids,
            token_type_ids=token_type_ids,
            position_ids=position_ids,
        )
        output = self.model.encoder(embeddings, attention_mask=None).last_hidden_state
        pooled = output.mean(dim=1)
        return torch.nn.functional.normalize(pooled, p=2, dim=1)


def convert(output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    tokenizer_dir = output_dir / "e5-tokenizer"
    tokenizer_dir.mkdir(parents=True, exist_ok=True)

    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID, attn_implementation="eager").eval()
    wrapped = MeanPooledE5(model).eval()

    input_ids = torch.ones(1, 32, dtype=torch.int32)
    token_type_ids = torch.zeros(1, 32, dtype=torch.int32)
    position_ids = torch.arange(2, 34, dtype=torch.int32).unsqueeze(0)
    traced = torch.jit.trace(wrapped, (input_ids, token_type_ids, position_ids))

    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(
                name="input_ids",
                shape=(1, ct.RangeDim(1, 512)),
                dtype=int,
            ),
            ct.TensorType(
                name="token_type_ids",
                shape=(1, ct.RangeDim(1, 512)),
                dtype=int,
            ),
            ct.TensorType(
                name="position_ids",
                shape=(1, ct.RangeDim(1, 512)),
                dtype=int,
            ),
        ],
        minimum_deployment_target=ct.target.macOS14,
        compute_units=ct.ComputeUnit.ALL,
    )

    mlmodel.save(output_dir / "multilingual-e5-small.mlpackage")
    tokenizer.save_pretrained(tokenizer_dir)
    print(output_dir)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(".build/Models/e5"),
        help="Directory for CoreML model package and tokenizer assets.",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    convert(args.output_dir)
