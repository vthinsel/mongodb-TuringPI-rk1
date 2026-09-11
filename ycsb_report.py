#!/usr/bin/env python3
"""Create aggregate charts and CSV data from saved go-ycsb thread results."""

import argparse
import csv
import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter


RESULT_RE = re.compile(
    r"^(?P<operation>READ|SCAN|UPDATE|INSERT(?:_ERROR)?|TOTAL)\s+-"
    r".*?Count:\s+(?P<count>\d+)"
    r", OPS:\s+(?P<ops>[\d.]+)"
    r", Avg\(us\):\s+(?P<avg>[\d.]+)"
    r".*?95th\(us\):\s+(?P<p95>[\d.]+)"
)
FILE_RE = re.compile(r"^(?P<prefix>.+)-threads-(?P<threads>\d+)\.txt$")


def format_metric_tick(value: float, _position: float) -> str:
    absolute_value = abs(value)
    for threshold, suffix in ((1_000_000_000, "G"), (1_000_000, "M"), (1_000, "K")):
        if absolute_value >= threshold:
            return f"{value / threshold:.1f}".rstrip("0").rstrip(".") + suffix
    return f"{value:.0f}"


def parse_results(results_dir: Path, prefix: str | None) -> list[dict[str, object]]:
    rows = []
    for path in sorted(results_dir.glob("*-threads-*.txt")):
        match = FILE_RE.match(path.name)
        if not match or (prefix and match.group("prefix") != prefix):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for line in text.splitlines():
            result = RESULT_RE.match(line)
            if result:
                rows.append(
                    {
                        "prefix": match.group("prefix"),
                        "threads": int(match.group("threads")),
                        "operation": result.group("operation"),
                        "count": int(result.group("count")),
                        "ops": float(result.group("ops")),
                        "avg_us": float(result.group("avg")),
                        "p95_us": float(result.group("p95")),
                    }
                )
    return rows


def write_csv(rows: list[dict[str, object]], output: Path) -> None:
    fields = ["prefix", "threads", "operation", "count", "ops", "avg_us", "p95_us"]
    with output.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def create_chart(rows: list[dict[str, object]], output: Path) -> None:
    prefixes = sorted({str(row["prefix"]) for row in rows})
    operations = ["TOTAL", "READ", "UPDATE", "SCAN"]
    fig, axes = plt.subplots(2, 2, figsize=(14, 9), constrained_layout=True)
    metrics = [("ops", "Throughput (ops/s)"), ("avg_us", "Average latency (us)"),
               ("p95_us", "95th percentile latency (us)"), ("count", "Operation count")]
    colors = {
        "TOTAL": "#1f77b4",
        "READ": "#2ca02c",
        "UPDATE": "#ff7f0e",
        "SCAN": "#d62728",
    }
    line_styles = {prefix: "-" if index == 0 else "--" for index, prefix in enumerate(prefixes)}

    for axis, (metric, title) in zip(axes.flat, metrics):
        for prefix in prefixes:
            for operation in operations:
                points = sorted(
                    (row for row in rows if row["prefix"] == prefix and row["operation"] == operation),
                    key=lambda row: int(row["threads"]),
                )
                if not points:
                    continue
                label = f"{prefix} {operation}" if len(prefixes) > 1 else operation
                axis.plot(
                    [row["threads"] for row in points],
                    [row[metric] for row in points],
                    marker="o",
                    color=colors[operation],
                    linestyle=line_styles[prefix],
                    label=label,
                )
        axis.set_title(title)
        axis.set_xlabel("YCSB client threads")
        axis.set_xticks(sorted({int(row["threads"]) for row in rows}))
        axis.yaxis.set_major_formatter(FuncFormatter(format_metric_tick))
        axis.grid(True, alpha=0.3)
        axis.legend(fontsize="small")

    fig.suptitle("YCSB thread-sweep summary")
    fig.savefig(output, dpi=160)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-dir", default="ycsb_results", type=Path)
    parser.add_argument("--prefix", help="Only report files with this prefix")
    parser.add_argument("--output-prefix", help="Output filename prefix; defaults to --prefix or 'ycsb'")
    args = parser.parse_args()

    rows = parse_results(args.results_dir, args.prefix)
    if not rows:
        raise SystemExit("No YCSB thread-sweep statistics found")
    output_prefix = args.output_prefix or args.prefix or "ycsb"
    csv_path = args.results_dir / f"{output_prefix}-summary.csv"
    png_path = args.results_dir / f"{output_prefix}-report.png"
    write_csv(rows, csv_path)
    create_chart(rows, png_path)
    print(f"Wrote {csv_path} and {png_path}")


if __name__ == "__main__":
    main()
