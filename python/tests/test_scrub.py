"""Tests for the sandbox scrub module.

The fixtures are minimized snippets of the worst audit offenders. Each test
checks one of:
  - Pass 1 strips comments without mangling string literals.
  - Pass 2 neutralizes fix-revealing diagnostic strings.
  - Per-knob: turning off `neutralize_*` keeps the matching strings intact.
  - `exclude_files` short-circuits — output is byte-identical to the input."""
from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import pytest

from dvbench.scrub import (
    FIX_REVEALING_DIAGNOSTIC_KEYWORDS,
    ScrubConfig,
    Scrubber,
    _discover_verible_preprocessor,
    neutralize_cpp_diagnostic_strings,
    neutralize_shell_echo_strings,
    neutralize_sv_diagnostic_strings,
    strip_c_style_comments,
    strip_line_comments,
)


def _verible_available() -> bool:
    try:
        _discover_verible_preprocessor()
        return True
    except FileNotFoundError:
        return False


# ---- ScrubConfig ------------------------------------------------------------


def test_scrub_config_defaults_to_full_scrub_when_json_key_missing():
    config = ScrubConfig.from_problem_json({"problem_id": "x"})
    assert config.strip_comments is True
    assert config.neutralize_display_strings is True
    assert config.neutralize_shell_echo_strings is True
    assert config.exclude_files == ()


def test_scrub_config_reads_per_knob_overrides_from_json():
    config = ScrubConfig.from_problem_json({
        "scrub": {
            "strip_comments": False,
            "neutralize_display_strings": False,
            "exclude_files": ["tb_one.sv", "tb_two.sv"],
        }
    })
    assert config.strip_comments is False
    assert config.neutralize_display_strings is False
    # Unspecified knob falls back to True.
    assert config.neutralize_shell_echo_strings is True
    assert config.exclude_files == ("tb_one.sv", "tb_two.sv")


# ---- Pass 1: SV comment stripping (via verible) -----------------------------


def test_pass_1_strips_sv_line_and_block_comments_via_verible(tmp_path: Path):
    """`verible-verilog-preprocessor strip-comments` replaces comments with
    whitespace and preserves string literals containing comment-looking text."""
    if not _verible_available():
        pytest.skip("verible-verilog-preprocessor not discoverable")

    sv_source = (
        "module foo;\n"
        "  // bug: comment that names the fix\n"
        '  initial $display("FAIL: real bug %d", 1);  /* trailing block bug */\n'
        "endmodule\n"
    )
    source_file_path = tmp_path / "src.sv"
    destination_file_path = tmp_path / "dst.sv"
    source_file_path.write_text(sv_source)

    Scrubber(ScrubConfig(neutralize_display_strings=False)).scrub_file(
        source_file_path, destination_file_path, "src.sv",
    )
    scrubbed_text = destination_file_path.read_text()

    # Comment-prefixed bug mention is gone.
    assert "comment that names the fix" not in scrubbed_text
    assert "trailing block bug" not in scrubbed_text
    # String literal is preserved exactly because Pass 2 is off.
    assert 'FAIL: real bug %d' in scrubbed_text


# ---- Pass 1: C-style comment stripping --------------------------------------


def test_strip_c_style_comments_drops_line_and_block_comments():
    cpp_source = (
        "int main() {\n"
        "  // fix: tweak\n"
        "  /* multi-\n"
        "     line bug note */\n"
        "  return 0;\n"
        "}\n"
    )
    scrubbed_text = strip_c_style_comments(cpp_source)
    assert "tweak" not in scrubbed_text
    assert "line bug note" not in scrubbed_text
    assert "return 0" in scrubbed_text


def test_strip_c_style_comments_preserves_strings_containing_slash_slash():
    cpp_source = 'const char *url = "http://example.com"; // bug\n'
    scrubbed_text = strip_c_style_comments(cpp_source)
    assert '"http://example.com"' in scrubbed_text
    assert "bug" not in scrubbed_text


# ---- Pass 1: shell + assembly line comments ---------------------------------


def test_strip_line_comments_drops_hash_lines_but_keeps_shebang_in_shell():
    shell_source = (
        "#!/usr/bin/env bash\n"
        "# Focused runner for the buggy thing\n"
        'echo "hello"\n'
    )
    scrubbed_text = strip_line_comments(
        shell_source, comment_prefixes=("#",), preserve_shebang=True,
    )
    assert scrubbed_text.startswith("#!/usr/bin/env bash\n")
    assert "Focused runner" not in scrubbed_text
    assert 'echo "hello"' in scrubbed_text


def test_strip_line_comments_drops_hash_and_slash_slash_in_assembly():
    asm_source = (
        ".text\n"
        "# the bug — buggy RTL traps here\n"
        "// another fix-revealing note\n"
        "_start: ebreak\n"
    )
    scrubbed_text = strip_line_comments(
        asm_source, comment_prefixes=("#", "//"), preserve_shebang=False,
    )
    assert "buggy RTL traps" not in scrubbed_text
    assert "fix-revealing" not in scrubbed_text
    assert "_start: ebreak" in scrubbed_text


# ---- Pass 2: SV diagnostic string neutralization ----------------------------


def test_neutralize_sv_diagnostic_strings_empties_fix_revealing_args_only():
    sv_source = (
        '$display("FAIL: WSTRB shift wrong — got 0x%02h, expected 0xF0", m_wstrb);\n'
        '$fatal(1, "axilupsz WSTRB byte-shift bug observed");\n'
        '$display("PASS");\n'
    )
    scrubbed_text = neutralize_sv_diagnostic_strings(sv_source)
    # Fix-revealing strings (contain "wrong", "bug") go empty.
    assert "WSTRB shift wrong" not in scrubbed_text
    assert "byte-shift bug" not in scrubbed_text
    # Non-string args (signal refs, severity codes) are preserved.
    assert "m_wstrb" in scrubbed_text
    assert re.search(r"\$fatal\s*\(\s*1\s*,", scrubbed_text) is not None
    # Innocuous strings stay verbatim — the bundled runners often grep
    # against `$display` output to decide pass/fail.
    assert '"PASS"' in scrubbed_text


def test_neutralize_sv_diagnostic_strings_handles_escaped_quotes():
    sv_source = '$display("she said \\"buggy\\" anyway");\n'
    scrubbed_text = neutralize_sv_diagnostic_strings(sv_source)
    assert '"she said' not in scrubbed_text
    assert "buggy" not in scrubbed_text


# ---- Pass 2: shell echo neutralization --------------------------------------


def test_neutralize_shell_echo_strings_drops_only_fix_revealing_strings():
    shell_source = (
        'echo "RESULT: buggy RTL accepted CSR_MCYCLE write." >&2\n'
        'echo "PASS"\n'
        'echo "FAIL"\n'
    )
    scrubbed_text = neutralize_shell_echo_strings(shell_source)
    assert "buggy RTL accepted" not in scrubbed_text
    # Innocuous strings stay verbatim — they're useful and don't leak the bug.
    assert '"PASS"' in scrubbed_text
    assert '"FAIL"' in scrubbed_text


# ---- Pass 2: C++ diagnostic neutralization ----------------------------------


def test_neutralize_cpp_diagnostic_strings_filters_by_keyword():
    cpp_source = (
        'printf("benign progress line\\n");\n'
        'printf("FAIL: real bug observed at addr 0x%x", addr);\n'
    )
    scrubbed_text = neutralize_cpp_diagnostic_strings(cpp_source)
    # Innocuous printf stays.
    assert "benign progress line" in scrubbed_text
    # Fix-revealing printf goes empty.
    assert "real bug observed" not in scrubbed_text


# ---- Per-knob behavior + exclude_files --------------------------------------


def test_disabling_display_neutralization_keeps_sv_strings_intact(tmp_path: Path):
    if not _verible_available():
        pytest.skip("verible-verilog-preprocessor not discoverable")
    sv_source = '$display("FAIL: real bug");\n'
    source_file_path = tmp_path / "src.sv"
    destination_file_path = tmp_path / "dst.sv"
    source_file_path.write_text(sv_source)

    Scrubber(ScrubConfig(neutralize_display_strings=False)).scrub_file(
        source_file_path, destination_file_path, "src.sv",
    )
    assert '"FAIL: real bug"' in destination_file_path.read_text()


def test_exclude_files_makes_scrub_a_byte_identical_copy(tmp_path: Path):
    raw_source = (
        '$display("FAIL: real bug");\n'
        '// header comment that names the fix\n'
    )
    source_file_path = tmp_path / "tb_neutral.sv"
    destination_file_path = tmp_path / "dst.sv"
    source_file_path.write_text(raw_source)

    Scrubber(ScrubConfig(exclude_files=("tb_neutral.sv",))).scrub_file(
        source_file_path, destination_file_path, "tb_neutral.sv",
    )
    assert destination_file_path.read_bytes() == source_file_path.read_bytes()


# ---- Sanity: every keyword in the audit gets caught -------------------------


def test_every_fix_revealing_keyword_triggers_shell_neutralization():
    for keyword in FIX_REVEALING_DIAGNOSTIC_KEYWORDS:
        shell_source = f'echo "this is {keyword} territory"\n'
        scrubbed_text = neutralize_shell_echo_strings(shell_source)
        assert keyword not in scrubbed_text, f"keyword {keyword!r} survived scrub"


# ---- Optional smoke check via `bash -n` -------------------------------------


def test_scrubbed_shell_still_parses_under_bash_n(tmp_path: Path):
    if shutil.which("bash") is None:
        pytest.skip("bash not available")
    shell_source = (
        "#!/usr/bin/env bash\n"
        "# Focused runner for the buggy thing\n"
        'echo "RESULT: buggy RTL did X" >&2\n'
        "exit 0\n"
    )
    source_file_path = tmp_path / "run.sh"
    destination_file_path = tmp_path / "scrubbed.sh"
    source_file_path.write_text(shell_source)

    Scrubber(ScrubConfig()).scrub_file(
        source_file_path, destination_file_path, "run.sh",
    )

    completed = subprocess.run(
        ["bash", "-n", str(destination_file_path)],
        capture_output=True, text=True,
    )
    assert completed.returncode == 0, completed.stderr
