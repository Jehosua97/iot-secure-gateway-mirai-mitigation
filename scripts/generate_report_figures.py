from __future__ import annotations

import re
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt
from matplotlib.lines import Line2D
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch, Rectangle


ROOT = Path(__file__).resolve().parents[1]
RESULTS_ROOT = ROOT / "docker-lab" / "results"
IMG_DIR = ROOT / "img"

COLORS = {
    "bg": "#F4F7FB",
    "text": "#16202A",
    "muted": "#5B6775",
    "blue": "#2B6CF0",
    "blue_light": "#DCE8FF",
    "green": "#2E9F6B",
    "green_light": "#DDF4E7",
    "orange": "#F28C28",
    "orange_light": "#FFE7CF",
    "red": "#D64545",
    "red_light": "#FFDCDD",
    "gray": "#8A97A6",
    "gray_light": "#E7EDF3",
}


def latest_results_dir() -> Path | None:
    if not RESULTS_ROOT.exists():
        return None

    candidates = [
        path
        for path in RESULTS_ROOT.iterdir()
        if path.is_dir() and re.fullmatch(r"\d{8}-\d{6}", path.name)
    ]
    return max(candidates, key=lambda item: item.name) if candidates else None


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def parse_connect_times(path: Path) -> list[int]:
    values: list[int] = []
    if not path.exists():
        return values

    for line in read_text(path).splitlines():
        match = re.search(r"connect_ms=(\d+)", line)
        if match:
            values.append(int(match.group(1)))
    return values


def parse_scale_result(path: Path) -> tuple[int, int] | None:
    if not path.exists():
        return None

    text = read_text(path)
    conn_match = re.search(r"parallel_connections=(\d+)", text)
    elapsed_match = re.search(r"elapsed_seconds=(\d+)", text)
    if conn_match and elapsed_match:
        return int(conn_match.group(1)), int(elapsed_match.group(1))
    return None


def parse_counter(path: Path, comment_fragment: str) -> int | None:
    if not path.exists():
        return None

    pattern = re.compile(
        rf'counter packets (\d+) bytes \d+ .*comment "{re.escape(comment_fragment)}"'
    )
    for line in read_text(path).splitlines():
        match = pattern.search(line)
        if match:
            return int(match.group(1))
    return None


def parse_memory_usage(path: Path) -> dict[str, float]:
    values: dict[str, float] = {}
    if not path.exists():
        return values

    for line in read_text(path).splitlines():
        match = re.search(
            r"\s(iot-fw|iot-device|attacker-outside)\s+\S+\s+([0-9.]+)MiB", line
        )
        if match:
            values[match.group(1)] = float(match.group(2))
    return values


def gather_metrics() -> dict[str, object]:
    latest = latest_results_dir()
    metrics: dict[str, object] = {
        "results_label": latest.name if latest else "manual-report-values",
        "connect_before": [3, 3, 3, 3, 2],
        "connect_after": [2, 2, 2, 2, 1],
        "scale_runs": [(10, 3), (25, 3), (50, 3)],
        "inbound_drop_after_inbound": 15,
        "outbound_block_after_outbound": 9,
        "https_allow_after_outbound": 5,
        "inbound_drop_after_scale": 185,
        "memory_before": {
            "iot-fw": 3.035,
            "iot-device": 3.219,
            "attacker-outside": 4.035,
        },
        "memory_after": {
            "iot-fw": 1.594,
            "iot-device": 3.211,
            "attacker-outside": 3.855,
        },
    }

    if latest is None:
        return metrics

    connect_before = parse_connect_times(latest / "iot-allowed-443-to-wan.stdout.txt")
    connect_after = parse_connect_times(
        latest / "iot-allowed-443-to-wan-after-scale.stdout.txt"
    )
    scale_runs = []
    for burst in (10, 25, 50):
        item = parse_scale_result(latest / f"atk-scale-{burst}.stdout.txt")
        if item is not None:
            scale_runs.append(item)

    inbound_drop_after_inbound = parse_counter(
        latest / "fw-forward-counters-after-inbound.stdout.txt",
        "block wan ssh telnet to iot",
    )
    outbound_block_after_outbound = parse_counter(
        latest / "fw-forward-counters-after-outbound.stdout.txt",
        "block iot ssh telnet outbound",
    )
    https_allow_after_outbound = parse_counter(
        latest / "fw-forward-counters-after-outbound.stdout.txt",
        "allow iot https to wan",
    )
    inbound_drop_after_scale = parse_counter(
        latest / "fw-forward-counters-after-scale.stdout.txt",
        "block wan ssh telnet to iot",
    )
    memory_before = parse_memory_usage(latest / "docker-stats-baseline.stdout.txt")
    memory_after = parse_memory_usage(latest / "docker-stats-after-scale.stdout.txt")

    if connect_before:
        metrics["connect_before"] = connect_before
    if connect_after:
        metrics["connect_after"] = connect_after
    if scale_runs:
        metrics["scale_runs"] = scale_runs
    if inbound_drop_after_inbound is not None:
        metrics["inbound_drop_after_inbound"] = inbound_drop_after_inbound
    if outbound_block_after_outbound is not None:
        metrics["outbound_block_after_outbound"] = outbound_block_after_outbound
    if https_allow_after_outbound is not None:
        metrics["https_allow_after_outbound"] = https_allow_after_outbound
    if inbound_drop_after_scale is not None:
        metrics["inbound_drop_after_scale"] = inbound_drop_after_scale
    if memory_before:
        metrics["memory_before"] = memory_before
    if memory_after:
        metrics["memory_after"] = memory_after

    return metrics


def base_figure(figsize: tuple[float, float]):
    fig, ax = plt.subplots(figsize=figsize, dpi=200)
    fig.patch.set_facecolor(COLORS["bg"])
    ax.set_facecolor(COLORS["bg"])
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 100)
    ax.axis("off")
    return fig, ax


def add_round_box(
    ax,
    x: float,
    y: float,
    w: float,
    h: float,
    color: str,
    title: str,
    lines: list[str],
    title_size: int = 15,
    body_size: int = 11,
) -> None:
    patch = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.9,rounding_size=6",
        linewidth=1.8,
        facecolor=color,
        edgecolor="white",
    )
    ax.add_patch(patch)
    ax.text(
        x + w / 2,
        y + h * 0.67,
        title,
        ha="center",
        va="center",
        color="white",
        fontsize=title_size,
        fontweight="bold",
    )
    if lines:
        ax.text(
            x + w / 2,
            y + h * 0.42,
            "\n".join(lines),
            ha="center",
            va="center",
            color="white",
            fontsize=body_size,
            linespacing=1.35,
            fontweight="bold",
        )


def add_pill(
    ax,
    x: float,
    y: float,
    w: float,
    h: float,
    label: str,
    fill: str,
    text_color: str = None,
    size: int = 10,
) -> None:
    patch = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.3,rounding_size=3",
        linewidth=1.0,
        facecolor=fill,
        edgecolor="none",
    )
    ax.add_patch(patch)
    ax.text(
        x + w / 2,
        y + h / 2,
        label,
        ha="center",
        va="center",
        fontsize=size,
        color=text_color or COLORS["text"],
        fontweight="bold",
    )


def add_arrow(
    ax,
    start: tuple[float, float],
    end: tuple[float, float],
    color: str,
    lw: float = 2.5,
    mutation_scale: float = 16,
    connectionstyle: str = "arc3,rad=0.0",
) -> None:
    arrow = FancyArrowPatch(
        start,
        end,
        arrowstyle="-|>",
        mutation_scale=mutation_scale,
        linewidth=lw,
        color=color,
        connectionstyle=connectionstyle,
    )
    ax.add_patch(arrow)


def add_cross(ax, x: float, y: float, size: float = 2.8) -> None:
    ax.add_line(Line2D([x - size, x + size], [y - size, y + size], lw=3, color=COLORS["red"]))
    ax.add_line(Line2D([x - size, x + size], [y + size, y - size], lw=3, color=COLORS["red"]))


def add_check(ax, x: float, y: float, size: float = 3.0) -> None:
    ax.add_line(
        Line2D(
            [x - size, x - size / 4, x + size],
            [y - size / 3, y - size, y + size / 2],
            lw=3.2,
            color=COLORS["green"],
        )
    )


def style_panel(ax, x: float, y: float, w: float, h: float, title: str) -> None:
    panel = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.8,rounding_size=4",
        facecolor="white",
        edgecolor=COLORS["gray_light"],
        linewidth=1.4,
    )
    ax.add_patch(panel)
    ax.text(
        x + 2,
        y + h - 4,
        title,
        ha="left",
        va="center",
        fontsize=13,
        fontweight="bold",
        color=COLORS["text"],
    )


def generate_high_level_topology(output_path: Path) -> None:
    fig, ax = base_figure((7.2, 9.0))

    ax.text(
        50,
        96,
        "Docker Lab Topology",
        ha="center",
        va="center",
        fontsize=18,
        fontweight="bold",
        color=COLORS["text"],
    )
    ax.text(
        50,
        91,
        "Three containers with the firewall as the only routing boundary",
        ha="center",
        va="center",
        fontsize=10.5,
        color=COLORS["muted"],
    )

    add_round_box(
        ax,
        21,
        69,
        58,
        15,
        COLORS["blue"],
        "atk",
        ["WAN host / attacker", "192.168.56.10"],
        title_size=19,
        body_size=12,
    )
    add_round_box(
        ax,
        21,
        39,
        58,
        18,
        COLORS["orange"],
        "fw",
        ["Firewall / gateway", "wan_net: 192.168.56.2", "iot_net: 10.20.0.1"],
        title_size=18,
        body_size=11.5,
    )
    add_round_box(
        ax,
        21,
        12,
        58,
        15,
        COLORS["green"],
        "iot",
        ["Protected IoT endpoint", "10.20.0.10"],
        title_size=19,
        body_size=12,
    )

    add_arrow(ax, (50, 69), (50, 57), COLORS["blue"])
    add_arrow(ax, (50, 39), (50, 27), COLORS["green"])

    add_pill(ax, 34, 60.5, 32, 5, "wan_net 192.168.56.0/24", COLORS["blue_light"], COLORS["blue"])
    add_pill(ax, 36, 30.5, 28, 5, "iot_net 10.20.0.0/24", COLORS["green_light"], COLORS["green"])

    ax.text(50, 6.5, "Default-deny forwarding with nftables", ha="center", va="center", fontsize=11.5, color=COLORS["text"], fontweight="bold")
    ax.text(50, 2.2, "Inbound SSH/Telnet-style traffic is blocked; outbound HTTPS is allowed", ha="center", va="center", fontsize=10.1, color=COLORS["muted"])

    fig.savefig(output_path, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)


def generate_addressing_topology(output_path: Path) -> None:
    fig, ax = base_figure((7.3, 9.2))

    ax.text(
        50,
        96,
        "Detailed Addressing and Routing",
        ha="center",
        va="center",
        fontsize=18,
        fontweight="bold",
        color=COLORS["text"],
    )

    wan_band = FancyBboxPatch(
        (6, 68),
        88,
        18,
        boxstyle="round,pad=0.6,rounding_size=6",
        facecolor=COLORS["blue_light"],
        edgecolor="none",
    )
    iot_band = FancyBboxPatch(
        (6, 16),
        88,
        18,
        boxstyle="round,pad=0.6,rounding_size=6",
        facecolor=COLORS["green_light"],
        edgecolor="none",
    )
    ax.add_patch(wan_band)
    ax.add_patch(iot_band)

    ax.text(50, 82, "wan_net 192.168.56.0/24", ha="center", va="center", fontsize=13, fontweight="bold", color=COLORS["blue"])
    ax.text(50, 30, "iot_net 10.20.0.0/24", ha="center", va="center", fontsize=13, fontweight="bold", color=COLORS["green"])

    add_round_box(
        ax,
        10,
        71,
        26,
        10,
        COLORS["blue"],
        "atk",
        ["192.168.56.10", "Route via 192.168.56.2"],
        title_size=14,
        body_size=10,
    )
    add_round_box(
        ax,
        64,
        71,
        22,
        10,
        COLORS["orange"],
        "fw eth1",
        ["192.168.56.2", "WAN side"],
        title_size=13,
        body_size=10,
    )
    add_round_box(
        ax,
        64,
        19,
        22,
        10,
        COLORS["orange"],
        "fw eth0",
        ["10.20.0.1", "IoT side"],
        title_size=13,
        body_size=10,
    )
    add_round_box(
        ax,
        10,
        19,
        26,
        10,
        COLORS["green"],
        "iot",
        ["10.20.0.10", "Default gw 10.20.0.1"],
        title_size=14,
        body_size=10,
    )

    firewall_core = FancyBboxPatch(
        (49.5, 35),
        18,
        30,
        boxstyle="round,pad=0.8,rounding_size=6",
        facecolor=COLORS["orange"],
        edgecolor="white",
        linewidth=1.8,
    )
    ax.add_patch(firewall_core)
    ax.text(
        58.5,
        50,
        "fw\nrouting\n+\nnftables",
        ha="center",
        va="center",
        fontsize=14,
        color="white",
        fontweight="bold",
        linespacing=1.25,
    )

    add_arrow(ax, (36, 76), (64, 76), COLORS["blue"])
    add_arrow(ax, (36, 24), (64, 24), COLORS["green"])
    add_arrow(ax, (75, 71), (67.5, 63), COLORS["orange"], connectionstyle="arc3,rad=0.0")
    add_arrow(ax, (75, 29), (67.5, 37), COLORS["orange"], connectionstyle="arc3,rad=0.0")

    ax.text(12, 60, "No direct WAN path\ninto iot_net", ha="left", va="center", fontsize=10.5, color=COLORS["red"], fontweight="bold")
    add_cross(ax, 32, 52, size=3.2)
    add_arrow(ax, (24, 71), (24, 37), COLORS["gray"], lw=2.0, mutation_scale=14)
    ax.text(13, 10, "Policy decisions happen in the firewall container only", ha="left", va="center", fontsize=10.5, color=COLORS["muted"])

    fig.savefig(output_path, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)


def generate_firewall_policy_flow(output_path: Path) -> None:
    fig, ax = base_figure((7.3, 9.4))

    ax.text(
        50,
        96,
        "Firewall Forwarding Policy",
        ha="center",
        va="center",
        fontsize=18,
        fontweight="bold",
        color=COLORS["text"],
    )

    add_round_box(ax, 8, 82, 20, 8, COLORS["blue"], "WAN", ["192.168.56.10"], body_size=10)
    add_round_box(ax, 72, 82, 20, 8, COLORS["green"], "IoT", ["10.20.0.10"], body_size=10)
    add_round_box(ax, 35, 16, 30, 68, COLORS["orange"], "fw", ["default-deny forward chain"], body_size=11)

    style_panel(ax, 10, 59, 80, 18, "Inbound management traffic")
    ax.text(17, 67, "WAN", fontsize=12, fontweight="bold", color=COLORS["blue"])
    ax.text(79, 67, "IoT", fontsize=12, fontweight="bold", color=COLORS["green"], ha="right")
    add_arrow(ax, (24, 66), (44, 66), COLORS["blue"])
    add_arrow(ax, (56, 66), (76, 66), COLORS["gray"])
    add_cross(ax, 50, 66)
    add_pill(ax, 30, 60.5, 40, 4.8, "Ports 22, 23, 2323 -> DROP", COLORS["red_light"], COLORS["red"])

    style_panel(ax, 10, 37, 80, 18, "Outbound management traffic")
    ax.text(17, 45, "IoT", fontsize=12, fontweight="bold", color=COLORS["green"])
    ax.text(79, 45, "WAN", fontsize=12, fontweight="bold", color=COLORS["blue"], ha="right")
    add_arrow(ax, (24, 44), (44, 44), COLORS["green"])
    add_arrow(ax, (56, 44), (76, 44), COLORS["gray"])
    add_cross(ax, 50, 44)
    add_pill(ax, 30, 38.5, 40, 4.8, "Ports 22, 23, 2323 -> DROP", COLORS["red_light"], COLORS["red"])

    style_panel(ax, 10, 15, 80, 18, "Legitimate outbound service")
    ax.text(17, 23, "IoT", fontsize=12, fontweight="bold", color=COLORS["green"])
    ax.text(79, 23, "WAN", fontsize=12, fontweight="bold", color=COLORS["blue"], ha="right")
    add_arrow(ax, (24, 22), (76, 22), COLORS["green"])
    add_check(ax, 50, 22, size=3.4)
    add_pill(ax, 34, 16.5, 32, 4.8, "Port 443 -> ACCEPT", COLORS["green_light"], COLORS["green"])
    ax.text(50, 10, "Return traffic for established flows is accepted", ha="center", va="center", fontsize=10.5, color=COLORS["muted"])

    fig.savefig(output_path, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)


def generate_phase3_summary(output_path: Path, metrics: dict[str, object]) -> None:
    connect_before = metrics["connect_before"]
    connect_after = metrics["connect_after"]
    scale_runs = metrics["scale_runs"]
    inbound_drop_after_inbound = metrics["inbound_drop_after_inbound"]
    outbound_block_after_outbound = metrics["outbound_block_after_outbound"]
    https_allow_after_outbound = metrics["https_allow_after_outbound"]
    inbound_drop_after_scale = metrics["inbound_drop_after_scale"]
    memory_before = metrics["memory_before"]
    memory_after = metrics["memory_after"]
    results_label = metrics["results_label"]

    fig = plt.figure(figsize=(8.2, 10.8), dpi=200)
    fig.patch.set_facecolor(COLORS["bg"])
    gs = fig.add_gridspec(3, 1, height_ratios=[1.0, 1.15, 1.0], hspace=0.28)

    panel1 = fig.add_subplot(gs[0])
    panel3 = fig.add_subplot(gs[2])
    for ax in (panel1, panel3):
        ax.set_facecolor("white")
        for spine in ax.spines.values():
            spine.set_color(COLORS["gray_light"])
            spine.set_linewidth(1.2)

    panel1.set_title("Accuracy", loc="left", fontsize=14, fontweight="bold", color=COLORS["text"], pad=10)
    categories = ["Inbound drop", "Outbound drop", "HTTPS allow"]
    values = [
        int(inbound_drop_after_inbound),
        int(outbound_block_after_outbound),
        int(https_allow_after_outbound),
    ]
    bar_colors = [COLORS["red"], COLORS["red"], COLORS["green"]]
    bars = panel1.bar(categories, values, color=bar_colors, width=0.58)
    panel1.set_ylabel("Packets", color=COLORS["muted"])
    panel1.tick_params(axis="x", labelsize=10)
    panel1.tick_params(axis="y", labelcolor=COLORS["muted"])
    panel1.grid(axis="y", alpha=0.2)
    for bar, value in zip(bars, values):
        panel1.text(
            bar.get_x() + bar.get_width() / 2,
            value + 0.5,
            str(value),
            ha="center",
            va="bottom",
            fontsize=10,
            fontweight="bold",
            color=COLORS["text"],
        )
    panel1.text(
        0.02,
        0.95,
        "nmap result: 22, 23, and 2323 reported as filtered",
        transform=panel1.transAxes,
        ha="left",
        va="top",
        fontsize=10,
        color=COLORS["muted"],
        bbox=dict(boxstyle="round,pad=0.35", fc=COLORS["blue_light"], ec="none"),
    )

    subgs = gs[1].subgridspec(1, 2, width_ratios=[1.5, 1.0], wspace=0.22)
    ax_line = fig.add_subplot(subgs[0])
    ax_mem = fig.add_subplot(subgs[1])
    for ax in (ax_line, ax_mem):
        ax.set_facecolor("white")
        for spine in ax.spines.values():
            spine.set_color(COLORS["gray_light"])
            spine.set_linewidth(1.2)

    runs = list(range(1, len(connect_before) + 1))
    ax_line.set_title("Efficiency", loc="left", fontsize=14, fontweight="bold", color=COLORS["text"], pad=10)
    ax_line.plot(runs, connect_before, marker="o", color=COLORS["orange"], linewidth=2.4, label="Baseline HTTPS")
    ax_line.plot(runs, connect_after, marker="o", color=COLORS["green"], linewidth=2.4, label="After scale burst")
    ax_line.set_xlabel("Run", color=COLORS["muted"])
    ax_line.set_ylabel("connect_ms", color=COLORS["muted"])
    ax_line.set_xlim(0.75, len(runs) + 0.25)
    ax_line.set_xticks(runs)
    ax_line.grid(alpha=0.25)
    ax_line.legend(frameon=False, fontsize=9, loc="upper right")
    ax_line.tick_params(axis="both", labelcolor=COLORS["muted"])

    ax_mem.set_title("Container memory (MiB)", loc="left", fontsize=12, fontweight="bold", color=COLORS["text"], pad=10)
    names = ["iot-fw", "iot-device", "attacker-outside"]
    y_positions = [2.2, 1.2, 0.2]
    before_vals = [float(memory_before.get(name, 0.0)) for name in names]
    after_vals = [float(memory_after.get(name, 0.0)) for name in names]
    ax_mem.barh([y + 0.16 for y in y_positions], before_vals, height=0.28, color=COLORS["orange"], label="Baseline")
    ax_mem.barh([y - 0.16 for y in y_positions], after_vals, height=0.28, color=COLORS["green"], label="After scale")
    ax_mem.set_yticks(y_positions, ["fw", "iot", "atk"])
    ax_mem.set_xlim(0, max(before_vals + after_vals) + 0.6)
    ax_mem.grid(axis="x", alpha=0.2)
    ax_mem.legend(frameon=False, fontsize=8, loc="lower right")
    ax_mem.tick_params(axis="x", labelcolor=COLORS["muted"])
    ax_mem.tick_params(axis="y", labelcolor=COLORS["muted"])
    for y, before_value, after_value in zip(y_positions, before_vals, after_vals):
        ax_mem.text(before_value + 0.06, y + 0.16, f"{before_value:.2f}", va="center", ha="left", fontsize=8.5, color=COLORS["muted"])
        ax_mem.text(after_value + 0.06, y - 0.16, f"{after_value:.2f}", va="center", ha="left", fontsize=8.5, color=COLORS["muted"])

    panel3.set_title("Scalability", loc="left", fontsize=14, fontweight="bold", color=COLORS["text"], pad=10)
    scale_labels = [str(item[0]) for item in scale_runs]
    scale_elapsed = [item[1] for item in scale_runs]
    bars = panel3.bar(scale_labels, scale_elapsed, color=COLORS["blue"], width=0.55)
    panel3.set_xlabel("Parallel blocked connections", color=COLORS["muted"])
    panel3.set_ylabel("Elapsed seconds", color=COLORS["muted"])
    panel3.grid(axis="y", alpha=0.25)
    panel3.tick_params(axis="both", labelcolor=COLORS["muted"])
    for bar, value in zip(bars, scale_elapsed):
        panel3.text(
            bar.get_x() + bar.get_width() / 2,
            value + 0.05,
            str(value),
            ha="center",
            va="bottom",
            fontsize=10,
            fontweight="bold",
            color=COLORS["text"],
        )
    panel3.text(
        0.97,
        0.92,
        f"Inbound drop counter\n{int(inbound_drop_after_inbound)} -> {int(inbound_drop_after_scale)} packets",
        transform=panel3.transAxes,
        ha="right",
        va="top",
        fontsize=10.5,
        color=COLORS["text"],
        bbox=dict(boxstyle="round,pad=0.4", fc=COLORS["orange_light"], ec="none"),
    )
    panel3.text(
        0.02,
        -0.23,
        f"Source: Automated Phase 3 evidence set ({results_label})",
        transform=panel3.transAxes,
        ha="left",
        va="top",
        fontsize=9.5,
        color=COLORS["muted"],
    )

    fig.savefig(output_path, bbox_inches="tight", facecolor=fig.get_facecolor())
    plt.close(fig)


def main() -> None:
    IMG_DIR.mkdir(exist_ok=True)
    metrics = gather_metrics()

    generate_high_level_topology(IMG_DIR / "docker-high-level-topology.png")
    generate_addressing_topology(IMG_DIR / "docker-addressing-topology.png")
    generate_firewall_policy_flow(IMG_DIR / "firewall-policy-flow.png")
    generate_phase3_summary(IMG_DIR / "phase3-results-summary.png", metrics)

    print("Generated figures:")
    for name in (
        "docker-high-level-topology.png",
        "docker-addressing-topology.png",
        "firewall-policy-flow.png",
        "phase3-results-summary.png",
    ):
        print((IMG_DIR / name).resolve())


if __name__ == "__main__":
    plt.rcParams["font.family"] = "DejaVu Sans"
    main()
