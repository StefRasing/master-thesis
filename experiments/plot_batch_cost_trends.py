"""Plot batch time, enumeration count and mean per-program cost on three axes.

Usage: python experiments/plot_batch_cost_trends.py [snapshot_dir] [output_dir]
Includes only test-solved runs selecting exactly the requested property count. Each metric
is averaged across eligible repetitions per problem-fold, then across folds.
"""
import argparse
from collections import defaultdict
import csv
import json
from pathlib import Path
from statistics import mean

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FuncFormatter

CAPS = (5, 10, 20, 40)
DEFAULT = Path(__file__).resolve().parents[1] / "data/phalcon_batch/daic-20261116"


def summarize(snapshot):
    summary = []
    for domain in ("strings", "bitvectors"):
        for cap in CAPS:
            groups = defaultdict(list)
            total = 0
            seen = set()
            for path in sorted((snapshot / "results" / domain / f"properties-{cap}.runs/results").glob("*.json")):
                record = json.loads(path.read_text())
                result, identity = record["result"], record["identity"]
                config = identity["configuration"]
                assert config["algorithm"] == "phalcon_batch"
                assert config["benchmark"] == domain
                assert result["effective_configuration"]["phalcon"]["max_number_of_properties"] == cap
                key = (config["run"], identity["problem"], identity["fold"])
                assert key not in seen
                seen.add(key)
                total += 1
                assert result["solved_test_examples"] == (
                    result["correct_test_examples"] == result["test_examples"]
                )
                if (result["solved_test_examples"] and len(result["heuristic"]) == cap
                        and result["programs_enumerated"] > 0):
                    seconds, programs = result["execution_time"], result["programs_enumerated"]
                    groups[key[1:]].append((seconds, programs, 1e6 * seconds / programs))
            assert total == (2245 if domain == "strings" else 3775)
            fold_means = [tuple(mean(row[i] for row in rows) for i in range(3)) for rows in groups.values()]
            assert fold_means
            summary.append(dict(
                domain=domain, properties=cap, problem_folds=len(groups),
                included_fold_runs=sum(map(len, groups.values())),
                excluded_fold_runs=total - sum(map(len, groups.values())),
                seconds=mean(row[0] for row in fold_means),
                programs=mean(row[1] for row in fold_means),
                microseconds_per_program=mean(row[2] for row in fold_means),
            ))
    return summary


def render(summary, output):
    fig, panels = plt.subplots(1, 2, figsize=(14, 5.5))
    fig.subplots_adjust(left=0.065, right=0.88, bottom=0.24, top=0.88, wspace=0.88)
    metrics = (
        ("seconds", "Execution time (s)", "#0072B2", "o", "-"),
        ("programs", "Programs enumerated", "#D55E00", "s", "--"),
        ("microseconds_per_program", "Time per program (μs)", "#009E73", "^", "-."),
    )
    handles = []
    for panel, domain in zip(panels, ("strings", "bitvectors")):
        rows = [row for row in summary if row["domain"] == domain]
        program_axis = panel.twinx()
        cost_axis = panel.twinx()
        cost_axis.spines["right"].set_position(("outward", 66))
        for ax, (metric, label, color, marker, style) in zip((panel, program_axis, cost_axis), metrics):
            line, = ax.plot(CAPS, [row[metric] for row in rows], color=color,
                            marker=marker, linestyle=style, linewidth=2, markersize=6, label=label)
            ax.set_ylabel(label, color=color, fontsize=10)
            ax.tick_params(axis="y", colors=color)
            ax.set_ylim(bottom=0)
            ax.spines["top"].set_visible(False)
            if metric == "programs":
                ax.yaxis.set_major_formatter(FuncFormatter(lambda value, _: f"{value / 1000:g}k"))
            if domain == "strings":
                handles.append(line)
        panel.set(title=f"{domain.capitalize()} · Test-solved folds", xlabel="Selected properties", xticks=CAPS, xlim=(2, 43))
        panel.grid(axis="x", color="#dddddd", alpha=0.5)
    fig.legend(handles=handles, loc="lower center", bbox_to_anchor=(0.5, 0.04),
               ncol=3, frameon=False)
    output.mkdir(parents=True, exist_ok=True)
    for extension in ("svg", "pdf", "png"):
        fig.savefig(output / f"07_cost_trends.{extension}", dpi=200)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("snapshot", nargs="?", type=Path, default=DEFAULT)
    parser.add_argument("output", nargs="?", type=Path)
    args = parser.parse_args()
    output = args.output or args.snapshot / "plots"
    summary = summarize(args.snapshot)
    render(summary, output)
    with (output / "07_cost_trends.tsv").open("w") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(summary[0]), delimiter="\t")
        writer.writeheader()
        writer.writerows(summary)
    for row in summary:
        print(row)


if __name__ == "__main__":
    main()
