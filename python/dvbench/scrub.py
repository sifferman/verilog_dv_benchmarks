"""Strip fix-revealing comments and diagnostic strings from testbench files.

When `prepare_sandbox_cli.py` materializes a sandbox for an LLM, it copies the
per-problem testbench files in from `problems/<owner>/<repo>/`. Those files
narrate the bug in their headers and in their `$display`/`$fatal`/`echo`
diagnostic strings, which would let a model "solve" the problem just by
reading them. This module rewrites the copies (never the source-of-truth
files) so the comments are gone and the diagnostic strings that name the bug
are neutralized."""
from __future__ import annotations

import re
import shutil
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

# Words that, when found inside a runtime diagnostic string, name the bug.
# Matched case-insensitive against the string's body.
FIX_REVEALING_DIAGNOSTIC_KEYWORDS = (
    "bug", "buggy", "fix", "fixed", "broken", "incorrect", "wrong",
)

# Verilog/SystemVerilog system tasks whose string arguments narrate state at
# runtime; same shape as printf/fprintf in C++.
SV_DIAGNOSTIC_SYSTEM_TASKS = ("$display", "$fatal", "$error", "$warning", "$info")

# C++ printers whose first string argument is a format string.
CPP_DIAGNOSTIC_FUNCTIONS = ("printf", "fprintf", "std::cout", "cout", "std::cerr", "cerr")

# Verible preprocessor candidates — checked in order, first hit wins.
VERIBLE_PREPROCESSOR_FALLBACK_PATHS = (
    Path.home() / "Utils" / "verible" / "bin" / "verible-verilog-preprocessor",
    Path("/usr/local/bin/verible-verilog-preprocessor"),
    Path("/opt/verible/bin/verible-verilog-preprocessor"),
)


@dataclass(frozen=True)
class ScrubConfig:
    """Per-problem knobs that control what `Scrubber` does. The defaults
    correspond to a full scrub; problem authors flip individual knobs off in
    the problem JSON when a testbench's diagnostics are already safe."""

    strip_comments: bool = True
    neutralize_display_strings: bool = True
    neutralize_shell_echo_strings: bool = True
    exclude_files: tuple[str, ...] = ()

    @classmethod
    def from_problem_json(cls, problem_json_data: dict) -> "ScrubConfig":
        scrub_json_section = problem_json_data.get("scrub")
        if scrub_json_section is None:
            return cls()
        return cls(
            strip_comments=scrub_json_section.get("strip_comments", True),
            neutralize_display_strings=scrub_json_section.get(
                "neutralize_display_strings", True
            ),
            neutralize_shell_echo_strings=scrub_json_section.get(
                "neutralize_shell_echo_strings", True
            ),
            exclude_files=tuple(scrub_json_section.get("exclude_files", ())),
        )


class Scrubber:
    """Scrubs one testbench file at a time. Construct with a `ScrubConfig`,
    then call `scrub_file(...)` per file. The scrubber is stateless across
    files; the same instance is safe to reuse for an entire sandbox build."""

    def __init__(self, config: ScrubConfig) -> None:
        self.config = config
        self._verible_preprocessor_path = _discover_verible_preprocessor()

    def scrub_file(
        self,
        source_file_path: Path,
        destination_file_path: Path,
        relative_path_inside_problem_dir: str,
    ) -> None:
        """Read `source_file_path`, write a scrubbed copy to
        `destination_file_path`. `relative_path_inside_problem_dir` is the
        path under `problems/<owner>/<repo>/` used to match `exclude_files`."""
        destination_file_path.parent.mkdir(parents=True, exist_ok=True)

        if relative_path_inside_problem_dir in self.config.exclude_files:
            shutil.copy2(source_file_path, destination_file_path)
            return

        original_file_contents = source_file_path.read_text()
        scrubbed_file_contents = self._scrub_text(
            original_file_contents, source_file_path.suffix
        )
        destination_file_path.write_text(scrubbed_file_contents)

    def _scrub_text(self, file_contents: str, file_suffix: str) -> str:
        if file_suffix in (".sv", ".v", ".svh", ".vh"):
            if self.config.strip_comments:
                file_contents = self._strip_sv_comments(file_contents)
            if self.config.neutralize_display_strings:
                file_contents = neutralize_sv_diagnostic_strings(file_contents)
            return file_contents
        if file_suffix in (".cpp", ".c", ".h", ".hpp"):
            if self.config.strip_comments:
                file_contents = strip_c_style_comments(file_contents)
            if self.config.neutralize_display_strings:
                file_contents = neutralize_cpp_diagnostic_strings(file_contents)
            return file_contents
        if file_suffix == ".S":
            if self.config.strip_comments:
                file_contents = strip_line_comments(
                    file_contents, comment_prefixes=("#", "//"),
                    preserve_shebang=False,
                )
            return file_contents
        if file_suffix == ".sh":
            if self.config.strip_comments:
                file_contents = strip_line_comments(
                    file_contents, comment_prefixes=("#",),
                    preserve_shebang=True,
                )
            if self.config.neutralize_shell_echo_strings:
                file_contents = neutralize_shell_echo_strings(file_contents)
            return file_contents
        if file_suffix in (".vlt",):
            # Verilator config — leave untouched (no diagnostics, no narrative).
            return file_contents
        raise ValueError(
            f"Scrubber has no rule for {file_suffix!r}; add one or list the file"
            f" in `exclude_files` of the problem's `scrub` config."
        )

    def _strip_sv_comments(self, file_contents: str) -> str:
        """Run `verible-verilog-preprocessor strip-comments` on the buffer."""
        completed_process = subprocess.run(
            [str(self._verible_preprocessor_path), "strip-comments", "-"],
            input=file_contents,
            capture_output=True,
            text=True,
            check=True,
        )
        return completed_process.stdout


def _discover_verible_preprocessor() -> Path:
    discovered_path = shutil.which("verible-verilog-preprocessor")
    if discovered_path is not None:
        return Path(discovered_path)
    for fallback_path in VERIBLE_PREPROCESSOR_FALLBACK_PATHS:
        if fallback_path.is_file():
            return fallback_path
    raise FileNotFoundError(
        "verible-verilog-preprocessor not found on PATH or in the usual fallback"
        " locations. Install verible (see hdl-tool-installer --verible) or add"
        " its bin directory to PATH."
    )


# ---- comment stripping (non-SV) ---------------------------------------------


def strip_c_style_comments(file_contents: str) -> str:
    """Strip `// ...` and `/* ... */` comments while preserving string and
    character literals. Comments are replaced with whitespace (a single space)
    so line and column offsets stay roughly comparable."""
    output_buffer: list[str] = []
    parser_index = 0
    file_length = len(file_contents)
    while parser_index < file_length:
        current_character = file_contents[parser_index]
        next_character = file_contents[parser_index + 1] if parser_index + 1 < file_length else ""
        if current_character == "/" and next_character == "/":
            while parser_index < file_length and file_contents[parser_index] != "\n":
                parser_index += 1
            output_buffer.append(" ")
            continue
        if current_character == "/" and next_character == "*":
            parser_index += 2
            while parser_index < file_length - 1 and not (
                file_contents[parser_index] == "*"
                and file_contents[parser_index + 1] == "/"
            ):
                parser_index += 1
            parser_index += 2
            output_buffer.append(" ")
            continue
        if current_character in ("'", '"'):
            quote_character = current_character
            output_buffer.append(current_character)
            parser_index += 1
            while parser_index < file_length:
                next_character_inside_string = file_contents[parser_index]
                output_buffer.append(next_character_inside_string)
                parser_index += 1
                if next_character_inside_string == "\\" and parser_index < file_length:
                    output_buffer.append(file_contents[parser_index])
                    parser_index += 1
                    continue
                if next_character_inside_string == quote_character:
                    break
            continue
        output_buffer.append(current_character)
        parser_index += 1
    return "".join(output_buffer)


def strip_line_comments(
    file_contents: str,
    *,
    comment_prefixes: tuple[str, ...],
    preserve_shebang: bool,
) -> str:
    """Drop every line whose first non-whitespace token is one of
    `comment_prefixes`. Optionally keep a `#!...` shebang on line 1."""
    surviving_lines: list[str] = []
    for line_index, file_line in enumerate(file_contents.splitlines(keepends=True)):
        stripped_line = file_line.lstrip()
        if line_index == 0 and preserve_shebang and stripped_line.startswith("#!"):
            surviving_lines.append(file_line)
            continue
        if any(stripped_line.startswith(prefix) for prefix in comment_prefixes):
            # Keep a blank line so source line numbers stay roughly in sync.
            surviving_lines.append("\n" if file_line.endswith("\n") else "")
            continue
        surviving_lines.append(file_line)
    return "".join(surviving_lines)


# ---- diagnostic-string neutralization ---------------------------------------


def neutralize_sv_diagnostic_strings(file_contents: str) -> str:
    """Replace string-literal arguments of `$display`/`$fatal`/`$error`/
    `$warning`/`$info` *whose body contains a fix-revealing keyword* with an
    empty string. Plain strings like `"PASS"` / `"FAIL"` stay intact — the
    bundled runners often `grep -q "PASS"` against the log to decide
    pass/fail, so scrubbing those would break the harness."""
    return _rewrite_call_argument_strings(
        file_contents,
        function_pattern=_build_function_pattern(SV_DIAGNOSTIC_SYSTEM_TASKS),
        keyword_filter=FIX_REVEALING_DIAGNOSTIC_KEYWORDS,
    )


def neutralize_cpp_diagnostic_strings(file_contents: str) -> str:
    """Same neutralization as SV, applied to C++ printers."""
    return _rewrite_call_argument_strings(
        file_contents,
        function_pattern=_build_function_pattern(CPP_DIAGNOSTIC_FUNCTIONS),
        keyword_filter=FIX_REVEALING_DIAGNOSTIC_KEYWORDS,
    )


def neutralize_shell_echo_strings(file_contents: str) -> str:
    """Rewrite `echo "..."` / `printf "..."` lines: any string argument whose
    body contains a fix-revealing keyword is replaced with `""`. Strings
    without those keywords (e.g. `echo "PASS"`) are kept verbatim."""
    rewritten_lines: list[str] = []
    for file_line in file_contents.splitlines(keepends=True):
        if re.search(r"\b(echo|printf)\b", file_line) is None:
            rewritten_lines.append(file_line)
            continue
        rewritten_lines.append(_rewrite_shell_strings_on_line(file_line))
    return "".join(rewritten_lines)


def _build_function_pattern(function_names: tuple[str, ...]) -> re.Pattern[str]:
    escaped_names = [re.escape(function_name) for function_name in function_names]
    return re.compile(rf"({'|'.join(escaped_names)})\s*\(")


def _rewrite_call_argument_strings(
    file_contents: str,
    *,
    function_pattern: re.Pattern[str],
    keyword_filter: tuple[str, ...] | None,
) -> str:
    """Find each match of `function_pattern`, parse forward through the
    argument list respecting nested parens and string literals, and replace
    each top-level string-literal argument with `""`.

    `keyword_filter`:
      - None      → neutralize every string-literal argument unconditionally.
      - tuple     → only neutralize strings whose body contains one of these
                    words (case-insensitive). Useful for languages where the
                    same printer carries both fix-revealing and innocuous
                    messages (.cpp, .sh)."""
    output_buffer: list[str] = []
    rewrite_cursor = 0
    for function_match in function_pattern.finditer(file_contents):
        output_buffer.append(file_contents[rewrite_cursor:function_match.end()])
        argument_list_end = _find_matching_paren(file_contents, function_match.end() - 1)
        if argument_list_end is None:
            # Mismatched paren — bail on this call site, keep source as-is.
            rewrite_cursor = function_match.end()
            continue
        argument_list_text = file_contents[function_match.end():argument_list_end]
        output_buffer.append(
            _rewrite_top_level_string_literals(argument_list_text, keyword_filter)
        )
        output_buffer.append(")")
        rewrite_cursor = argument_list_end + 1
    output_buffer.append(file_contents[rewrite_cursor:])
    return "".join(output_buffer)


def _find_matching_paren(file_contents: str, open_paren_index: int) -> int | None:
    assert file_contents[open_paren_index] == "("
    paren_depth = 1
    scan_index = open_paren_index + 1
    file_length = len(file_contents)
    while scan_index < file_length:
        current_character = file_contents[scan_index]
        if current_character == '"':
            scan_index = _skip_string_literal(file_contents, scan_index) + 1
            continue
        if current_character == "(":
            paren_depth += 1
        elif current_character == ")":
            paren_depth -= 1
            if paren_depth == 0:
                return scan_index
        scan_index += 1
    return None


def _skip_string_literal(file_contents: str, opening_quote_index: int) -> int:
    """Return the index of the closing `"` of the string literal starting at
    `opening_quote_index`. Honors `\\"` escapes."""
    scan_index = opening_quote_index + 1
    file_length = len(file_contents)
    while scan_index < file_length:
        if file_contents[scan_index] == "\\" and scan_index + 1 < file_length:
            scan_index += 2
            continue
        if file_contents[scan_index] == '"':
            return scan_index
        scan_index += 1
    return file_length - 1


def _rewrite_top_level_string_literals(
    argument_list_text: str,
    keyword_filter: tuple[str, ...] | None,
) -> str:
    """Walk `argument_list_text` and replace every string literal at paren
    depth 0 with `""`, optionally only when its body matches the filter."""
    output_buffer: list[str] = []
    parser_index = 0
    text_length = len(argument_list_text)
    paren_depth = 0
    while parser_index < text_length:
        current_character = argument_list_text[parser_index]
        if current_character == "(":
            paren_depth += 1
            output_buffer.append(current_character)
            parser_index += 1
            continue
        if current_character == ")":
            paren_depth -= 1
            output_buffer.append(current_character)
            parser_index += 1
            continue
        if current_character == '"' and paren_depth == 0:
            closing_quote_index = _skip_string_literal(argument_list_text, parser_index)
            string_body = argument_list_text[parser_index + 1:closing_quote_index]
            if keyword_filter is None or _contains_any_keyword(string_body, keyword_filter):
                output_buffer.append('""')
            else:
                output_buffer.append(argument_list_text[parser_index:closing_quote_index + 1])
            parser_index = closing_quote_index + 1
            continue
        output_buffer.append(current_character)
        parser_index += 1
    return "".join(output_buffer)


def _rewrite_shell_strings_on_line(shell_line: str) -> str:
    """For a single shell line containing echo/printf, replace each
    double-quoted string whose body contains a fix-revealing keyword with `""`."""
    output_buffer: list[str] = []
    parser_index = 0
    line_length = len(shell_line)
    while parser_index < line_length:
        current_character = shell_line[parser_index]
        if current_character == '"':
            closing_quote_index = _skip_string_literal(shell_line, parser_index)
            string_body = shell_line[parser_index + 1:closing_quote_index]
            if _contains_any_keyword(string_body, FIX_REVEALING_DIAGNOSTIC_KEYWORDS):
                output_buffer.append('""')
            else:
                output_buffer.append(shell_line[parser_index:closing_quote_index + 1])
            parser_index = closing_quote_index + 1
            continue
        output_buffer.append(current_character)
        parser_index += 1
    return "".join(output_buffer)


def _contains_any_keyword(string_body: str, keywords: tuple[str, ...]) -> bool:
    lowercased_body = string_body.lower()
    return any(
        re.search(rf"\b{re.escape(keyword)}\b", lowercased_body) is not None
        for keyword in keywords
    )
