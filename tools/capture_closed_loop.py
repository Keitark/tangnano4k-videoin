import csv
import sys
import time
from collections import Counter
from pathlib import Path

import cv2
import numpy as np


DEVICE_INDEX = 0
CAPTURE_SECONDS = 8.0


def classify_status(frame):
    # New HDMI-health strip: seven fixed 80-pixel color blocks followed by an
    # HPLL block. Verify the fixed signature first so ordinary picture colors
    # cannot be mistaken for status.
    segments = [
        frame[0:8, start:start + 80, :].mean(axis=(0, 1))
        for start in range(0, 640, 80)
    ]
    blue0, green0, red0 = segments[0]
    blue1, green1, red1 = segments[1]
    blue2, green2, red2 = segments[2]
    blue3, green3, red3 = segments[3]
    blue4, green4, red4 = segments[4]
    blue5, green5, red5 = segments[5]
    blue6, green6, red6 = segments[6]
    health_strip = (
        blue0 > 150 and green0 > 150 and red0 > 150 and
        blue1 < 100 and green1 > 150 and red1 > 150 and
        blue2 > 150 and green2 > 150 and red2 < 100 and
        blue3 < 100 and green3 > 150 and red3 < 100 and
        blue4 > 150 and green4 < 100 and red4 > 150 and
        blue5 < 100 and green5 < 100 and red5 > 150 and
        blue6 > 150 and green6 < 100 and red6 < 100
    )
    if health_strip:
        blue7, green7, red7 = segments[7]
        if blue7 < 100 and green7 > 120 and red7 > 150:
            return "locked"
        return "unlocked"

    blue, green, red = frame[8:60, :, :].mean(axis=(0, 1))
    if green > 120 and red < 100:
        return "locked"
    if red > 120 and green > 70:
        return "activity"
    if red > 120:
        return "inactive"
    return "unknown"


def decode_threshold(frame):
    band = frame[99:107, :, :].mean(axis=0)
    blue, green, red = band[:, 0], band[:, 1], band[:, 2]
    active = (blue > 80) & (green > 80) & (red < 80)
    width = 0
    for pixel_active in active:
        if not pixel_active:
            break
        width += 1
    code = int(round((width - 8) / 2.0))
    return code if 0 <= code <= 255 else None


def decode_reference(frame):
    band = frame[76:92, :, :].mean(axis=0)
    blue, green, red = band[:, 0], band[:, 1], band[:, 2]
    active = (blue > 80) & (red > 80) & (green < 100)
    width = 0
    for pixel_active in active:
        if not pixel_active:
            break
        width += 1
    code = int(round((width - 8) / 2.0))
    return code if 0 <= code <= 255 else None


def main():
    label = sys.argv[1] if len(sys.argv) > 1 else "normal"
    if label not in (
        "normal", "inverted", "sweep", "feedback_low", "feedback_high",
        "ntsc_decoder", "loop_runs", "sweep_broad", "sweep_probe",
        "period_sweep",
        "filtered_period_sweep",
        "coherent_filtered_sweep",
        "coherent_repeat_sweep",
        "coherent_33pf_sweep",
        "coherent_33pf_iir_sweep",
        "coherent_33pf_iir64_sweep",
        "coherent_33pf_iir64_replug",
        "coherent_33pf_iir64_powercycle",
        "coherent_33pf_period234",
        "coherent_33pf_period_histogram",
        "coherent_33pf_hysteresis_histogram",
        "coherent_33pf_center_sweep",
        "coherent_33pf_fixed224_stats",
        "coherent_33pf_fixed224_period_histogram",
        "coherent_33pf_fixed224_period_histogram_guard700",
        "coherent_33pf_fixed224_period_histogram_guard700_wide",
        "ntsc_qualified_edge_decoder",
        "ntsc_qualified_edge_decoder_guard700",
        "ntsc_qualified_edge_decoder_guard800",
        "ntsc_qualified_edge_decoder_center148",
        "ntsc_center148_freerun858",
        "ntsc_center148_freerun858_fixedblack160",
        "ntsc_center148_freerun858_fixedblack200",
        "ntsc_center148_phasewindow820_luma32",
        "ntsc_center148_hpll_pi",
        "ntsc_center148_hpll_phase_diag",
        "ntsc_center148_hpll_unmasked",
        "ntsc_center148_hpll_black185_gain8",
        "ntsc_center148_hpll_raw_level_activity",
        "ntsc_center148_hpll_width_qualified",
        "ntsc_center148_hpll_width_iir3",
        "ntsc_center148_hpll_width_iir4",
        "ntsc_center148_hpll_iir4_tight_pi",
        "ntsc_center148_hpll_iir4_width60_70",
        "ntsc_hlocked_backporch_luma",
        "ntsc_hlocked_backporch_luma32",
        "ntsc_hlocked_level_markers",
        "ntsc_hlocked_inverted_luma",
        "ntsc_hlocked_filtered_level_luma",
        "ntsc_hlocked_triple_line_store",
        "ntsc_hlocked_filtered_raw_triple",
        "ntsc_hlocked_filtered_raw_triple_livecheck",
        "ntsc_hlocked_coherent_level_hold",
        "ntsc_hlocked_coherent_monochrome",
        "ntsc_hlocked_coherent_raw_postreboot",
        "ntsc_hpll_reacquire_raw",
        "ntsc_hpll_raw_width_telemetry",
        "ntsc_hpll_full_width_telemetry",
        "ntsc_hpll_interval_qualified",
        "ntsc_hpll_fast_sync_filter",
        "ntsc_hpll_interval_monochrome",
        "ntsc_hpll_coherent_density_raw",
        "ntsc_hpll_coherent_density_monochrome",
        "ntsc_hpll_coherent_density_luma_unity",
        "ntsc_hpll_coherent_density_luma_unity_guard840",
        "ntsc_hpll_coherent_density_luma_unity_hdmi_reset",
        "ntsc_dualpath_flywheel_min32",
        "ntsc_dualpath_flywheel_min32_statusbar",
        "ntsc_dualpath_flywheel_statusbar",
        "ntsc_dualpath_cadence3_flywheel_statusbar",
        "ntsc_dualpath_cadence3_flywheel_track24",
        "ntsc_dualpath_cadence3_flywheel_slowpi",
        "ntsc_dualpath_cadence3_flywheel_slowpi_regionlock",
        "ntsc_dualpath_cadence3_flywheel_slowpi_regionlock_fly16",
        "ntsc_dualpath_cadence3_flywheel_slowpi_regionlock_fly16_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_hanchor_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_rawlevel_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_rawinvert_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_rawinvert_ioff_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_slow4_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_fbdiv2_vcadence_11of21",
        "ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_iir4_vcadence_11of21",
    ):
        raise ValueError(
            "label must be normal, inverted, sweep, feedback_low, feedback_high, "
            "ntsc_decoder, loop_runs, sweep_broad, sweep_probe, period_sweep, "
            "filtered_period_sweep, coherent_filtered_sweep, coherent_repeat_sweep, "
            "coherent_33pf_sweep, coherent_33pf_iir_sweep, or "
            "coherent_33pf_iir64_sweep, coherent_33pf_iir64_replug, or "
            "coherent_33pf_iir64_powercycle, coherent_33pf_period234, or "
            "coherent_33pf_period_histogram, coherent_33pf_hysteresis_histogram, or "
            "coherent_33pf_center_sweep, coherent_33pf_fixed224_stats, or "
            "coherent_33pf_fixed224_period_histogram, or "
            "coherent_33pf_fixed224_period_histogram_guard700, or "
            "coherent_33pf_fixed224_period_histogram_guard700_wide, or "
            "ntsc_qualified_edge_decoder, ntsc_qualified_edge_decoder_guard700, or "
            "ntsc_qualified_edge_decoder_guard800, or "
            "ntsc_qualified_edge_decoder_center148, ntsc_center148_freerun858, or "
            "ntsc_center148_freerun858_fixedblack160, or "
            "ntsc_center148_freerun858_fixedblack200, or "
            "ntsc_center148_phasewindow820_luma32, ntsc_center148_hpll_pi, or "
            "ntsc_center148_hpll_phase_diag, ntsc_center148_hpll_unmasked, or "
            "ntsc_center148_hpll_black185_gain8, or "
            "ntsc_center148_hpll_raw_level_activity, or "
            "ntsc_center148_hpll_width_qualified, or "
            "ntsc_center148_hpll_width_iir3, or "
            "ntsc_center148_hpll_width_iir4, or "
            "ntsc_center148_hpll_iir4_tight_pi, or "
            "ntsc_center148_hpll_iir4_width60_70, or "
            "ntsc_hlocked_backporch_luma, ntsc_hlocked_backporch_luma32, or "
            "ntsc_hlocked_level_markers, ntsc_hlocked_inverted_luma, or "
            "ntsc_hlocked_filtered_level_luma, ntsc_hlocked_triple_line_store, or "
            "ntsc_hlocked_filtered_raw_triple"
            ", ntsc_hlocked_filtered_raw_triple_livecheck"
            ", ntsc_hlocked_coherent_level_hold"
            ", ntsc_hlocked_coherent_monochrome"
            ", ntsc_hlocked_coherent_raw_postreboot"
            ", ntsc_hpll_reacquire_raw"
            ", ntsc_hpll_raw_width_telemetry"
            ", ntsc_hpll_full_width_telemetry"
            ", ntsc_hpll_interval_qualified"
            ", ntsc_hpll_fast_sync_filter"
            ", ntsc_hpll_interval_monochrome"
            ", ntsc_hpll_coherent_density_raw"
            ", ntsc_hpll_coherent_density_monochrome"
            ", ntsc_hpll_coherent_density_luma_unity"
            ", ntsc_hpll_coherent_density_luma_unity_guard840"
            ", ntsc_hpll_coherent_density_luma_unity_hdmi_reset"
            ", ntsc_dualpath_flywheel_min32"
            ", ntsc_dualpath_flywheel_min32_statusbar"
            ", ntsc_dualpath_flywheel_statusbar"
            ", ntsc_dualpath_cadence3_flywheel_statusbar"
            ", ntsc_dualpath_cadence3_flywheel_track24"
            ", ntsc_dualpath_cadence3_flywheel_slowpi"
            ", ntsc_dualpath_cadence3_flywheel_slowpi_regionlock"
            ", ntsc_dualpath_cadence3_flywheel_slowpi_regionlock_fly16"
            ", ntsc_dualpath_cadence3_flywheel_slowpi_regionlock_fly16_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_hanchor_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_rawlevel_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_rawinvert_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_rawinvert_ioff_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_slow4_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_fbdiv2_vcadence_11of21"
            ", ntsc_lowres128x120_doublebuffer4_freerun858_rawinvert_iir4_vcadence_11of21"
        )

    repo_root = Path(__file__).resolve().parents[1]
    output_dir = repo_root / "build" / f"closed_loop_{label}_capture"
    output_dir.mkdir(parents=True, exist_ok=True)

    capture = cv2.VideoCapture(DEVICE_INDEX, cv2.CAP_MSMF)
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    capture.set(cv2.CAP_PROP_FPS, 60)
    if not capture.isOpened():
        raise RuntimeError(f"MSMF capture index {DEVICE_INDEX} did not open")

    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = capture.get(cv2.CAP_PROP_FPS) or 30.0
    writer = cv2.VideoWriter(
        str(output_dir / "capture.avi"),
        cv2.VideoWriter_fourcc(*"MJPG"),
        fps,
        (width, height),
    )

    rows = []
    first_frame = None
    locked_frame = None
    failures = 0
    consecutive_failures = 0
    started = time.monotonic()
    while time.monotonic() - started < CAPTURE_SECONDS:
        ok, frame = capture.read()
        if not ok:
            failures += 1
            consecutive_failures += 1
            if consecutive_failures >= 120:
                break
            time.sleep(0.01)
            continue
        consecutive_failures = 0
        writer.write(frame)
        status = classify_status(frame)
        reference = decode_reference(frame)
        threshold = decode_threshold(frame)
        top = frame[8:60, :, :].mean(axis=(0, 1))
        level = frame[270:400, :, :].mean(axis=(0, 1))
        bottom = frame[450:478, :, :].mean(axis=(0, 1))
        rows.append((time.monotonic() - started, status, reference, threshold,
                     *top, *level, *bottom))
        if first_frame is None:
            first_frame = frame.copy()
        if status != "unknown" and locked_frame is None:
            locked_frame = frame.copy()

    capture.release()
    writer.release()

    with (output_dir / "metrics.csv").open("w", newline="", encoding="utf-8") as handle:
        output = csv.writer(handle)
        output.writerow(
            [
                "seconds", "status", "reference", "threshold",
                "top_b", "top_g", "top_r",
                "level_b", "level_g", "level_r",
                "bottom_b", "bottom_g", "bottom_r",
            ]
        )
        for row in rows:
            output.writerow(
                [f"{row[0]:.6f}", row[1], row[2], row[3],
                 *[f"{value:.3f}" for value in row[4:]]]
            )

    representative = locked_frame if locked_frame is not None else first_frame
    if representative is not None:
        cv2.imwrite(str(output_dir / "representative.png"), representative)

    statuses = Counter(row[1] for row in rows)
    references = Counter(row[2] for row in rows if row[2] is not None)
    thresholds = Counter(row[3] for row in rows if row[3] is not None)
    print(f"label={label} capture={width}x{height}@{fps:.3f} frames={len(rows)} failures={failures}")
    print(f"statuses={dict(statuses)}")
    print(f"references={dict(references)}")
    print(f"thresholds={dict(thresholds)}")
    if rows:
        print(f"final_status={rows[-1][1]}")


if __name__ == "__main__":
    main()
