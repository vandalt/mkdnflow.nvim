#!/usr/bin/env python3
"""
generate_docs.py - Documentation generator for Mkdnflow

Renders documentation from YAML source files in scripts/docs/ into:
  - README.md (GitHub-flavored markdown)
  - doc/mkdnflow.txt (Vim help file)

Usage:
  python3 scripts/generate_docs.py
  # or
  make docs

Content is defined in YAML files (sections.yaml, config.yaml, commands.yaml,
api.yaml, metadata.yaml) and a Lua file (default_config.lua). This script
provides the rendering logic using content primitives (Prose, CodeBlock,
BulletList, Table, etc.) and two formatters: ReadmeFormatter and VimdocFormatter.

To update documentation:
  1. Edit the appropriate YAML file in scripts/docs/
  2. Run this script to regenerate both outputs
  3. Commit both the YAML changes and generated files

Author: Jake W. Vincent
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional, Union, Any, Dict
from textwrap import wrap, dedent, indent
from abc import ABC, abstractmethod
import os
import re
import sys
import yaml


# =============================================================================
# YAML LOADING INFRASTRUCTURE
# =============================================================================

def get_docs_path() -> str:
    """Get the path to the docs directory."""
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, "docs")


def load_yaml(filename: str) -> Any:
    """Load a YAML file from the docs directory."""
    docs_path = get_docs_path()
    filepath = os.path.join(docs_path, filename)
    if not os.path.exists(filepath):
        return None
    with open(filepath, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_lua_file(filename: str) -> str:
    """Load a Lua file from the docs directory."""
    docs_path = get_docs_path()
    filepath = os.path.join(docs_path, filename)
    if not os.path.exists(filepath):
        return None
    with open(filepath, "r", encoding="utf-8") as f:
        return f.read().strip()


def yaml_to_config_option(data: Dict[str, Any]) -> ConfigOption:
    """Convert a YAML dict to a ConfigOption dataclass."""
    # Add backticks around name and type if not already present
    name = data['name']
    if not name.startswith('`'):
        name = f"`{name}`"

    type_str = data['type']
    if not type_str.startswith('`'):
        # Handle types with parenthetical notes: "table (array-like)" -> "`table` (array-like)"
        paren_match = re.match(r'^(\w+)\s+(\(.+\))$', type_str)
        if paren_match:
            type_str = f"`{paren_match.group(1)}` {paren_match.group(2)}"
        # Handle union types: "string | boolean" -> "`string` | `boolean`"
        elif ' | ' in type_str:
            parts = type_str.split(' | ')
            type_str = ' | '.join(f'`{p.strip()}`' for p in parts)
        else:
            type_str = f"`{type_str}`"

    return ConfigOption(
        name=name,
        type=type_str,
        description=data['description'].strip(),
    )


def yaml_to_command(data: Dict[str, Any]) -> Command:
    """Convert a YAML dict to a Command dataclass."""
    mapping = data.get('default_mapping')
    if mapping is None:
        mapping = '--'
    elif not mapping.startswith('`'):
        mapping = f"`{mapping}`"
    return Command(
        name=f"`{data['name']}`",
        default_mapping=mapping,
        description=data['description'].strip(),
    )


def yaml_to_api_param(data: Dict[str, Any]) -> ApiParam:
    """Convert a YAML dict to an ApiParam dataclass."""
    children = [yaml_to_api_param(c) for c in data.get('children', [])]
    return ApiParam(
        name=data['name'],
        type=data['type'],
        description=data['description'],
        children=children,
    )


def yaml_to_api_function(data: Dict[str, Any]) -> ApiFunction:
    """Convert a YAML dict to an ApiFunction dataclass."""
    params = [yaml_to_api_param(p) for p in data.get('params', [])]
    return ApiFunction(
        signature=data['signature'],
        description=data['description'].strip(),
        params=params,
        example=data.get('example', '').strip() if data.get('example') else '',
    )


def load_commands_from_yaml() -> Optional[List[Command]]:
    """Load commands from YAML file, returns None if file doesn't exist."""
    data = load_yaml("commands.yaml")
    if data is None:
        return None
    return [yaml_to_command(cmd) for cmd in data.get('commands', [])]


def load_config_options_from_yaml(group: str) -> Optional[List[ConfigOption]]:
    """Load config options for a specific group from YAML file."""
    data = load_yaml("config.yaml")
    if data is None:
        return None
    group_data = data.get(group, [])
    return [yaml_to_config_option(opt) for opt in group_data]


def load_default_config_from_lua() -> Optional[str]:
    """Load default config from Lua file."""
    return load_lua_file("default_config.lua")


def get_commands() -> List[Command]:
    """Get commands from commands.yaml."""
    commands = load_commands_from_yaml()
    if commands is None:
        raise FileNotFoundError("scripts/docs/commands.yaml is required")
    return commands


def get_config_options(group: str) -> List[ConfigOption]:
    """Get config options for a group from config.yaml."""
    options = load_config_options_from_yaml(group)
    if options is None:
        raise FileNotFoundError("scripts/docs/config.yaml is required")
    return options


def get_default_config() -> str:
    """Get default config from default_config.lua."""
    config = load_default_config_from_lua()
    if config is None:
        raise FileNotFoundError("scripts/docs/default_config.lua is required")
    return config


def load_api_functions_from_yaml(category: str) -> List[ApiFunction]:
    """Load API functions for a specific category from api.yaml."""
    data = load_yaml("api.yaml")
    if data is None:
        raise FileNotFoundError("scripts/docs/api.yaml is required")
    category_data = data.get(category, [])
    return [yaml_to_api_function(func) for func in category_data]


def yaml_to_list_item(data: Dict[str, Any]) -> ListItem:
    """Convert YAML dict to ListItem."""
    children = [yaml_to_list_item(c) for c in data.get('children', [])]
    return ListItem(
        text=data['text'],
        done=data.get('done'),
        children=children,
    )


def yaml_to_content(data: Dict[str, Any]) -> Content:
    """Convert a YAML content dict to the appropriate Content type."""
    content_type = data.get('type')

    if content_type == 'prose':
        return Prose(data['text'])

    elif content_type == 'code':
        return CodeBlock(data['code'], data.get('language', 'lua'))

    elif content_type == 'list':
        items = [yaml_to_list_item(item) for item in data.get('items', [])]
        return BulletList(items, data.get('ordered', False))

    elif content_type == 'table':
        return Table(
            headers=data['headers'],
            rows=data['rows'],
            alignments=data.get('alignments'),
        )

    elif content_type == 'admonition':
        return Admonition(data['kind'], data['content'])

    elif content_type == 'collapsible':
        content = [yaml_to_content(c) for c in data.get('content', [])]
        return Collapsible(data['summary'], content)

    elif content_type == 'image':
        return Image(
            url=data['url'],
            alt=data.get('alt', ''),
            centered=data.get('centered', False),
        )

    elif content_type == 'responsive_image':
        return ResponsiveImage(
            light_url=data['light'],
            dark_url=data['dark'],
            alt=data.get('alt', ''),
            centered=data.get('centered', False),
        )

    elif content_type == 'badges':
        return Badges(
            urls=data['items'],
            centered=data.get('centered', True),
        )

    elif content_type == 'config_table':
        ref = data['ref']
        return ConfigOptionTable(options=get_config_options(ref))

    elif content_type == 'command_table':
        return CommandTable(commands=get_commands())

    elif content_type == 'api_section':
        # Reference to API functions from api.yaml
        ref = data['ref']
        funcs = load_api_functions_from_yaml(ref)
        if funcs:
            # Return the list of ApiFunction objects as content items
            # This is a special case - we return a list and handle it in yaml_to_section
            return funcs
        return []

    elif content_type == 'default_config':
        return CodeBlock(get_default_config())

    else:
        raise ValueError(f"Unknown content type: {content_type}")


def yaml_to_section(data: Dict[str, Any]) -> Section:
    """Convert a YAML section dict to a Section dataclass."""
    content = []
    for item in data.get('content', []):
        result = yaml_to_content(item)
        # Handle api_section which returns a list
        if isinstance(result, list):
            content.extend(result)
        else:
            content.append(result)

    children = [yaml_to_section(c) for c in data.get('children', [])]

    return Section(
        title=data['title'],
        tag=data['tag'],
        emoji=data.get('emoji', ''),
        content=content,
        children=children,
    )


def load_sections_from_yaml() -> Optional[List[Section]]:
    """Load sections from YAML file."""
    data = load_yaml("sections.yaml")
    if data is None:
        return None
    return [yaml_to_section(s) for s in data.get('sections', [])]


# =============================================================================
# CONTENT PRIMITIVES
# =============================================================================
@dataclass
class Prose:
    """A block of paragraph text."""

    text: str

    def __post_init__(self):
        # Normalize whitespace from triple-quoted strings
        self.text = dedent(self.text).strip()


@dataclass
class CodeBlock:
    """A fenced code block."""

    code: str
    language: str = "lua"

    def __post_init__(self):
        self.code = dedent(self.code).strip()


@dataclass
class ListItem:
    """A single list item, possibly with children."""

    text: str
    done: Optional[bool] = None  # None = not a task, True/False = task status
    children: List["ListItem"] = field(default_factory=list)


@dataclass
class BulletList:
    """An ordered or unordered list."""

    items: List[ListItem]
    ordered: bool = False


@dataclass
class Table:
    """A data table."""

    headers: List[str]
    rows: List[List[str]]
    alignments: Optional[List[str]] = None  # 'left', 'center', 'right'


@dataclass
class Link:
    """A hyperlink or internal reference."""

    text: str
    target: str
    internal: bool = False  # True for internal doc references


@dataclass
class Admonition:
    """A note, warning, or tip callout."""

    kind: str  # 'note', 'warning', 'tip'
    content: str

    def __post_init__(self):
        self.content = dedent(self.content).strip()


@dataclass
class Collapsible:
    """Content that's collapsible in README, flat in vimdoc."""

    summary: str
    content: List["Content"]


@dataclass
class ConfigOption:
    """A configuration option with its details."""

    name: str
    type: str
    description: str


@dataclass
class ConfigOptionTable:
    """A table of configuration options loaded from CSV."""

    options: List[ConfigOption]


@dataclass
class Command:
    """A vim command with description."""

    name: str
    description: str
    default_mapping: str = ""


@dataclass
class CommandTable:
    """A table of commands."""

    commands: List[Command]


@dataclass
class Image:
    """An image that only renders in README, omitted in vimdoc."""

    url: str
    alt: str = ""
    centered: bool = False


@dataclass
class ResponsiveImage:
    """A <picture> element with dark/light mode variants. Omitted in vimdoc."""

    light_url: str
    dark_url: str
    alt: str = ""
    centered: bool = False


@dataclass
class Badges:
    """A row of badge images (shields.io style). Omitted in vimdoc."""

    urls: List[str]
    centered: bool = True


@dataclass
class ApiParam:
    """A parameter for an API function."""

    name: str
    type: str
    description: str
    children: List["ApiParam"] = field(default_factory=list)


@dataclass
class ApiFunction:
    """An API function with signature, description, and parameters."""

    signature: str  # e.g., "require('mkdnflow').setup(config)"
    description: str
    params: List[ApiParam] = field(default_factory=list)
    example: str = ""  # Optional code example


# Union type for all content
Content = Union[
    Prose,
    CodeBlock,
    BulletList,
    Table,
    Link,
    Admonition,
    Collapsible,
    ConfigOption,
    ConfigOptionTable,
    Command,
    CommandTable,
    Image,
    ResponsiveImage,
    Badges,
    ApiFunction,
    "Section",
]


@dataclass
class Section:
    """A documentation section with optional children."""

    title: str
    tag: str  # vimdoc tag (without Mkdnflow- prefix)
    emoji: str = ""
    content: List[Content] = field(default_factory=list)
    children: List["Section"] = field(default_factory=list)
    level: int = 1  # heading level, set during rendering



# =============================================================================
# FORMATTER BASE
# =============================================================================


class Formatter(ABC):
    """Base class for output formatters."""

    @abstractmethod
    def format_document(self, sections: List[Section]) -> str:
        pass

    @abstractmethod
    def format_section(self, section: Section, level: int) -> str:
        pass

    @abstractmethod
    def format_prose(self, prose: Prose) -> str:
        pass

    @abstractmethod
    def format_code_block(self, block: CodeBlock) -> str:
        pass

    @abstractmethod
    def format_list(self, lst: BulletList) -> str:
        pass

    @abstractmethod
    def format_table(self, table: Table) -> str:
        pass

    @abstractmethod
    def format_admonition(self, admon: Admonition) -> str:
        pass

    @abstractmethod
    def format_collapsible(self, coll: Collapsible) -> str:
        pass

    @abstractmethod
    def format_config_option_table(self, table: ConfigOptionTable) -> str:
        pass

    @abstractmethod
    def format_command_table(self, table: CommandTable) -> str:
        pass

    @abstractmethod
    def format_image(self, img: Image) -> str:
        pass

    @abstractmethod
    def format_responsive_image(self, img: ResponsiveImage) -> str:
        pass

    @abstractmethod
    def format_badges(self, badges: Badges) -> str:
        pass

    @abstractmethod
    def format_api_function(self, func: ApiFunction) -> str:
        pass

    def format_content(self, content: Content) -> str:
        """Dispatch to the appropriate format method."""
        if isinstance(content, Prose):
            return self.format_prose(content)
        elif isinstance(content, CodeBlock):
            return self.format_code_block(content)
        elif isinstance(content, BulletList):
            return self.format_list(content)
        elif isinstance(content, Table):
            return self.format_table(content)
        elif isinstance(content, Admonition):
            return self.format_admonition(content)
        elif isinstance(content, Collapsible):
            return self.format_collapsible(content)
        elif isinstance(content, ConfigOptionTable):
            return self.format_config_option_table(content)
        elif isinstance(content, CommandTable):
            return self.format_command_table(content)
        elif isinstance(content, Image):
            return self.format_image(content)
        elif isinstance(content, ResponsiveImage):
            return self.format_responsive_image(content)
        elif isinstance(content, Badges):
            return self.format_badges(content)
        elif isinstance(content, ApiFunction):
            return self.format_api_function(content)
        elif isinstance(content, Section):
            return self.format_section(content, content.level)
        else:
            raise ValueError(f"Unknown content type: {type(content)}")


# =============================================================================
# VIMDOC FORMATTER
# =============================================================================


class VimdocFormatter(Formatter):
    """Formats documentation as vim help file."""

    WIDTH = 78
    TAG_PREFIX = "Mkdnflow-"

    def __init__(self):
        self.toc_entries = []

    # --- Helpers ---

    def tag(self, name: str) -> str:
        """Format a vimdoc tag."""
        return f"*{self.TAG_PREFIX}{name}*"

    def ref(self, name: str) -> str:
        """Format a vimdoc reference."""
        return f"|{self.TAG_PREFIX}{name}|"

    def right_align(self, left: str, right: str, width: int = None) -> str:
        """Create a line with left and right-aligned content."""
        width = width or self.WIDTH
        padding = width - len(left) - len(right)
        if padding < 1:
            padding = 1
        return f"{left}{' ' * padding}{right}"

    def hard_wrap(self, text: str, width: int = None, initial_indent: int = 0, subsequent_indent: int = 0) -> str:
        """Hard-wrap text to specified width, handling multiple paragraphs."""
        width = width or self.WIDTH
        paragraphs = text.split("\n\n")
        result_paragraphs = []

        for para in paragraphs:
            # Normalize whitespace within paragraph
            para = " ".join(para.split())
            if not para:
                continue

            lines = wrap(
                para,
                width=width,
                initial_indent=" " * initial_indent,
                subsequent_indent=" " * subsequent_indent,
            )
            result_paragraphs.append("\n".join(lines))

        return "\n\n".join(result_paragraphs)

    def separator(self, char: str = "=") -> str:
        """Create a full-width separator line."""
        return char * self.WIDTH

    def clean_for_vimdoc(self, text: str) -> str:
        """Clean markdown formatting for vimdoc output."""
        # Remove markdown bold
        text = re.sub(r"\*\*`([^`]+)`\*\*\*?:?", r"`\1`:", text)
        text = re.sub(r"\*\*([^*]+)\*\*", r"\1", text)
        # Remove markdown links, keep text
        text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
        # Convert "see `tagname`" patterns to vimdoc references
        text = re.sub(
            r"see `([a-z][a-z0-9-]*)`\)",
            lambda m: f"see |{self.TAG_PREFIX}{m.group(1)}|)",
            text,
        )
        # Convert <br> to newlines
        text = text.replace("<br>", "\n")
        # Remove HTML tags
        text = re.sub(r"<[^>]+>", "", text)
        # Clean up emoji note markers
        text = re.sub(r"🛈\s*", "Note: ", text)
        return text

    # --- Document structure ---

    def format_document(self, sections: List[Section]) -> str:
        """Format the complete vimdoc."""
        parts = []

        # Header
        parts.append(self.format_header())
        parts.append("")

        # Table of contents
        self.toc_entries = []
        self._collect_toc(sections, 1)
        parts.append(self.format_toc())
        parts.append("")

        # Sections
        for section in sections:
            parts.append(self.format_section(section, 1))

        # Footer
        parts.append("")
        parts.append("vim:tw=78:ts=8:ft=help:norl:")

        return "\n".join(parts)

    def format_header(self) -> str:
        """Format the vimdoc header."""
        lines = [
            "*Mkdnflow.nvim* Tools for fluent navigation and management of notebooks written",
            "in markdown",
            "",
            "          _|      _| _|    _| _|_|_|   _|      _| _   _                ~",
            "          _|_|  _|_| _|  _|   _|    _| _|_|    _|| | | |               ~",
            "          _|  _|  _| _|_|     _|    _| _|  _|  _|| | | |  __           ~",
            "          _|      _| _|  _|   _|    _| _|    _|_||/  |/  /  \\_|  |  |_ ~",
            "          _|      _| _|    _| _|_|_|   _|      _||__/|__/\\__/  \\/ \\/   ~",
            "                                                 |\\                    ~",
            "                                                 |/                    ~",
            "                                                 '                     ~",
            self.separator(),
            self.right_align("MKDNFLOW.NVIM REFERENCE", "*mkdnflow-reference*"),
            "",
            f"Author: Jake Vincent (jake@jwv.dev)                            {self.tag('author')}",
            f"Website: github.com/jakewvincent/mkdnflow.nvim                 {self.tag('website')}",
            f"License: GPL-3.0 (see |{self.TAG_PREFIX}license|)",
        ]
        return "\n".join(lines)

    def _collect_toc(self, sections: List[Section], level: int):
        """Recursively collect TOC entries."""
        for section in sections:
            # Only include level 1 and 2 in TOC
            if level <= 2:
                self.toc_entries.append((section.title, section.tag, level))
            if section.children:
                self._collect_toc(section.children, level + 1)

    def format_toc(self) -> str:
        """Format the table of contents."""
        lines = [
            self.separator(),
            self.right_align("CONTENTS", self.tag("contents")),
            "",
        ]

        for title, tag, depth in self.toc_entries:
            indent_str = "  " * (depth - 1)
            ref = self.ref(tag)
            left = f"{indent_str}{title}"
            # Create dot leader
            dots_width = self.WIDTH - len(left) - len(ref) - 2
            dots = "." * max(dots_width, 3)
            lines.append(f"{left} {dots} {ref}")

        return "\n".join(lines)

    def format_section(self, section: Section, level: int) -> str:
        """Format a section with heading and content."""
        parts = []

        # Section heading
        if level == 1:
            parts.append("")
            parts.append(self.separator())
            parts.append(self.right_align(section.title.upper(), self.tag(section.tag)))
        elif level == 2:
            parts.append("")
            parts.append(self.separator("-"))
            parts.append(self.right_align(section.title, self.tag(section.tag)))
        elif level == 3:
            parts.append("")
            parts.append(section.title.upper() + "~")
        else:
            parts.append("")
            parts.append(section.title + " ~")

        parts.append("")

        # Content
        for content in section.content:
            formatted = self.format_content(content)
            if formatted:
                parts.append(formatted)
                parts.append("")

        # Children
        for child in section.children:
            parts.append(self.format_section(child, level + 1))

        return "\n".join(parts)

    # --- Content formatting ---

    def format_prose(self, prose: Prose) -> str:
        text = self.clean_for_vimdoc(prose.text)
        return self.hard_wrap(text)

    def format_code_block(self, block: CodeBlock) -> str:
        lines = [">"]
        for line in block.code.split("\n"):
            lines.append(f"    {line}")
        lines.append("<")
        return "\n".join(lines)

    def format_list(self, lst: BulletList) -> str:
        lines = []
        for i, item in enumerate(lst.items):
            if lst.ordered:
                prefix = f"{i + 1}. "
            elif item.done is not None:
                marker = "x" if item.done else " "
                prefix = f"[{marker}] "
            else:
                prefix = "- "

            text = self.clean_for_vimdoc(item.text)
            # Wrap item text with hanging indent
            wrapped = wrap(text, width=self.WIDTH - len(prefix))
            lines.append(prefix + wrapped[0] if wrapped else prefix)
            for continuation in wrapped[1:]:
                lines.append(" " * len(prefix) + continuation)

            # Handle children with increased indent
            for child in item.children:
                child_text = self.clean_for_vimdoc(child.text)
                if child.done is not None:
                    marker = "x" if child.done else " "
                    child_prefix = f"    [{marker}] "
                else:
                    child_prefix = "    - "
                wrapped = wrap(child_text, width=self.WIDTH - len(child_prefix))
                lines.append(child_prefix + (wrapped[0] if wrapped else ""))
                for continuation in wrapped[1:]:
                    lines.append(" " * len(child_prefix) + continuation)

        return "\n".join(lines)

    def format_table(self, table: Table) -> str:
        """Format a table with proper column alignment."""
        # Calculate column widths
        all_rows = [table.headers] + table.rows
        col_widths = []
        for col_idx in range(len(table.headers)):
            max_width = max(len(str(row[col_idx])) for row in all_rows if col_idx < len(row))
            col_widths.append(min(max_width, 30))  # Cap column width

        def format_row(row):
            cells = []
            for i, cell in enumerate(row):
                if i < len(col_widths):
                    cells.append(str(cell)[: col_widths[i]].ljust(col_widths[i]))
            return "  ".join(cells)

        lines = [format_row(table.headers)]
        lines.append("  ".join("-" * w for w in col_widths))
        for row in table.rows:
            lines.append(format_row(row))

        return "\n".join(lines)

    def format_admonition(self, admon: Admonition) -> str:
        label = admon.kind.upper()
        text = self.clean_for_vimdoc(admon.content)
        wrapped = self.hard_wrap(text, initial_indent=4, subsequent_indent=4)
        return f"{label}:\n{wrapped}"

    def format_collapsible(self, coll: Collapsible) -> str:
        # In vimdoc, collapsibles are just rendered flat
        parts = [coll.summary.upper() + "~", ""]
        for content in coll.content:
            formatted = self.format_content(content)
            if formatted:
                parts.append(formatted)
                parts.append("")
        return "\n".join(parts)

    def format_config_option_table(self, table: ConfigOptionTable) -> str:
        """Format configuration options for vimdoc."""
        lines = []
        for opt in table.options:
            # Clean the option name (remove backticks)
            name = opt.name.strip("`")
            opt_type = opt.type.strip("`")
            description = self.clean_for_vimdoc(opt.description)
            # Treat single newlines in config descriptions as paragraph breaks,
            # matching the <br> behavior in the README table formatter
            description = re.sub(r'(?<!\n)\n(?!\n)', '\n\n', description)

            # Create tag from option name
            tag_name = "config-" + name.replace(".", "-").replace("_", "-")

            lines.append(self.right_align(name, self.tag(tag_name)))
            lines.append(f"    Type: {opt_type}")
            lines.append("")

            # Wrap description with indent
            wrapped = self.hard_wrap(description, initial_indent=4, subsequent_indent=4)
            lines.append(wrapped)
            lines.append("")

        return "\n".join(lines)

    def format_command_table(self, table: CommandTable) -> str:
        """Format commands for vimdoc."""
        lines = []
        for cmd in table.commands:
            # Clean the command name
            name = cmd.name.strip("`")
            description = self.clean_for_vimdoc(cmd.description)
            # Treat single newlines in command descriptions as paragraph breaks,
            # matching the <br> behavior in the README table formatter
            description = re.sub(r'(?<!\n)\n(?!\n)', '\n\n', description)

            # Create tag from command name
            tag_name = "cmd-" + name

            lines.append(self.right_align(f":{name}", self.tag(tag_name)))
            if cmd.default_mapping and cmd.default_mapping != "--":
                mapping = cmd.default_mapping.strip("`")
                lines.append(f"    Default mapping: {mapping}")
            lines.append("")

            # Wrap description with indent
            wrapped = self.hard_wrap(description, initial_indent=4, subsequent_indent=4)
            lines.append(wrapped)
            lines.append("")

        return "\n".join(lines)

    def format_image(self, img: Image) -> str:
        """Images are omitted in vimdoc."""
        return ""

    def format_responsive_image(self, img: ResponsiveImage) -> str:
        """Responsive images are omitted in vimdoc."""
        return ""

    def format_badges(self, badges: Badges) -> str:
        """Badges are omitted in vimdoc."""
        return ""

    def format_api_function(self, func: ApiFunction) -> str:
        """Format an API function for vimdoc."""
        lines = []

        # Function signature with tag
        # Create tag from function signature (e.g., require('mkdnflow').setup -> mkdnflow-setup)
        sig_parts = func.signature.split(".")
        if len(sig_parts) > 1:
            # Get the module and function name for the tag
            module_and_func = sig_parts[-1].split("(")[0]
            if len(sig_parts) > 2:
                # e.g., require('mkdnflow').links.createLink -> links-createLink
                tag_name = f"{sig_parts[-2]}-{module_and_func}"
            else:
                tag_name = module_and_func
        else:
            tag_name = func.signature.split("(")[0]

        # Clean up tag name
        tag_name = tag_name.replace("'", "").replace("(", "").replace(")", "")

        lines.append(f"`{func.signature}`^")
        lines.append("")
        lines.append("")

        # Description
        desc = self.clean_for_vimdoc(func.description)
        wrapped = self.hard_wrap(desc)
        lines.append(wrapped)

        # Parameters
        if func.params:
            lines.append("")
            lines.append("- **Parameters:**")
            for param in func.params:
                param_line = f"    - `{param.name}`: ({param.type}) {param.description}"
                lines.append(param_line)
                # Handle nested parameters
                for child in param.children:
                    child_line = f"        - `{child.name}`: ({child.type}) {child.description}"
                    lines.append(child_line)

        # Example code if provided
        if func.example:
            lines.append("")
            lines.append(">")
            for line in func.example.split("\n"):
                lines.append(line)
            lines.append("<")

        return "\n".join(lines)


# =============================================================================
# README FORMATTER
# =============================================================================


class ReadmeFormatter(Formatter):
    """Formats documentation as GitHub-flavored markdown."""

    def __init__(self):
        self.toc_entries = []
        self.toc_counter = 0
        self.tag_lookup = {}  # Maps tag -> (title, emoji) for cross-references

    def format_document(self, sections: List[Section]) -> str:
        """Format the complete README."""
        parts = []

        # Build tag lookup for cross-references (all sections, not just TOC)
        self.tag_lookup = {}
        self._build_tag_lookup(sections)

        # Header with logo, badges
        parts.append(self.format_header())
        parts.append("")

        # Table of contents
        self.toc_entries = []
        self.toc_counter = 0
        self._collect_toc(sections, 1)
        parts.append(self.format_toc())
        parts.append("")

        # Sections
        for section in sections:
            parts.append(self.format_section(section, 1))

        return "\n".join(parts)

    def _build_tag_lookup(self, sections: List[Section]):
        """Recursively build a lookup table mapping tags to (title, emoji)."""
        for section in sections:
            if section.tag:
                self.tag_lookup[section.tag] = (section.title, section.emoji or "")
            if section.children:
                self._build_tag_lookup(section.children)

    def format_header(self) -> str:
        """Format README header with logo and badges."""
        return dedent(
            """
            <p align="center">
                <picture>
                  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/logo/mkdnflow_logo_dark.png">
                  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/logo/mkdnflow_logo_light.png">
                  <img alt="Black mkdnflow logo in light color mode and white logo in dark color mode" src="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/logo/mkdnflow_logo_light.png">
                </picture>
            </p>
            <p align=center>
                <img src="https://img.shields.io/badge/Lua-2C2D72?style=for-the-badge&logo=lua&logoColor=white">
                <img src="https://img.shields.io/badge/Markdown-000000?style=for-the-badge&logo=markdown&logoColor=white">
                <img src="https://img.shields.io/badge/NeoVim-%2357A143.svg?&style=for-the-badge&logo=neovim&logoColor=white">
            </p>
        """
        ).strip()

    def _collect_toc(self, sections: List[Section], level: int):
        """Recursively collect TOC entries."""
        for section in sections:
            self.toc_counter += 1
            if level <= 2:  # Only top 2 levels in TOC
                self.toc_entries.append((section.title, section.emoji, section.tag, level, self.toc_counter))
            if section.children:
                self._collect_toc(section.children, level + 1)

    def format_toc(self) -> str:
        """Format table of contents."""
        lines = ["### Contents", ""]
        counter = 0
        for title, emoji, tag, depth, _ in self.toc_entries:
            if depth == 1:
                counter += 1
            indent_str = "    " * (depth - 1)
            anchor = self._make_anchor(title, emoji)
            emoji_prefix = f"{emoji} " if emoji else ""
            if depth == 1:
                lines.append(f"{counter}. [{emoji_prefix}{title}](#{anchor})")
            else:
                lines.append(f"{indent_str}1. [{emoji_prefix}{title}](#{anchor})")
        return "\n".join(lines)

    def _make_anchor(self, title: str, emoji: str = "") -> str:
        """Create a GitHub-compatible anchor link."""
        # GitHub treats emojis specially - they get replaced with empty string
        # but a leading space before title becomes a leading dash
        if emoji:
            # Emoji + space + title becomes "-title" in GitHub anchors
            anchor = f"-{title}"
        else:
            anchor = title
        # GitHub anchor generation rules
        anchor = anchor.lower()
        anchor = re.sub(r"[^\w\s-]", "", anchor)  # Remove special chars except hyphen
        anchor = re.sub(r"\s+", "-", anchor)  # Replace spaces with hyphens
        return anchor

    def format_section(self, section: Section, level: int) -> str:
        """Format a section."""
        parts = []

        # Heading
        emoji_prefix = f"{section.emoji} " if section.emoji else ""
        hashes = "#" * (level + 1)  # ## for level 1, ### for level 2, etc.
        parts.append(f"{hashes} {emoji_prefix}{section.title}")
        parts.append("")

        # Content
        for content in section.content:
            formatted = self.format_content(content)
            if formatted:
                parts.append(formatted)
                parts.append("")

        # Children
        for child in section.children:
            parts.append(self.format_section(child, level + 1))

        return "\n".join(parts)

    # --- Content formatting ---

    def _convert_cross_refs(self, text: str) -> str:
        """Convert `see `tagname`` patterns to markdown links."""
        def replace_ref(match):
            tag = match.group(1)
            if tag in self.tag_lookup:
                title, emoji = self.tag_lookup[tag]
                anchor = self._make_anchor(title, emoji)
                # Format as markdown link
                display = f"{emoji} {title}" if emoji else title
                return f"[{display}](#{anchor}))"
            # Tag not found, keep as backtick
            return match.group(0)

        # Match pattern: see `tagname`)
        return re.sub(r"see `([a-z][a-z0-9-]*)`\)", replace_ref, text)

    def format_prose(self, prose: Prose) -> str:
        text = prose.text
        # Convert cross-references to markdown links
        text = self._convert_cross_refs(text)
        return text

    def format_code_block(self, block: CodeBlock) -> str:
        return f"```{block.language}\n{block.code}\n```"

    def format_list(self, lst: BulletList) -> str:
        lines = []
        for i, item in enumerate(lst.items):
            if lst.ordered:
                prefix = f"{i + 1}. "
            elif item.done is not None:
                prefix = f"- [{'x' if item.done else ' '}] "
            else:
                prefix = "- "

            # Convert cross-references in list item text
            item_text = self._convert_cross_refs(item.text)
            lines.append(prefix + item_text)

            for child in item.children:
                if child.done is not None:
                    child_prefix = f"    - [{'x' if child.done else ' '}] "
                else:
                    child_prefix = "    - "
                child_text = self._convert_cross_refs(child.text)
                lines.append(child_prefix + child_text)

        return "\n".join(lines)

    def format_table(self, table: Table) -> str:
        """Format a markdown table."""

        def escape_pipes(text):
            return str(text).replace("|", "\\|")

        def format_row(row):
            return "| " + " | ".join(escape_pipes(cell) for cell in row) + " |"

        lines = [format_row(table.headers)]

        # Separator row
        alignments = table.alignments or ["left"] * len(table.headers)
        sep_cells = []
        for align in alignments:
            if align == "center":
                sep_cells.append(":---:")
            elif align == "right":
                sep_cells.append("---:")
            else:
                sep_cells.append("---")
        lines.append("| " + " | ".join(sep_cells) + " |")

        for row in table.rows:
            lines.append(format_row(row))

        return "\n".join(lines)

    def format_admonition(self, admon: Admonition) -> str:
        kind_map = {"note": "NOTE", "warning": "WARNING", "tip": "TIP"}
        label = kind_map.get(admon.kind, admon.kind.upper())
        # Format multi-line content with > prefix
        content_lines = admon.content.split("\n")
        formatted_lines = [f"> {line}" if line else ">" for line in content_lines]
        return f"> [!{label}]\n" + "\n".join(formatted_lines)

    def format_collapsible(self, coll: Collapsible) -> str:
        parts = [
            "<details>",
            f"<summary>{coll.summary}</summary>",
            "",
        ]
        for content in coll.content:
            formatted = self.format_content(content)
            if formatted:
                parts.append(formatted)
                parts.append("")
        parts.append("</details>")
        return "\n".join(parts)

    def format_config_option_table(self, table: ConfigOptionTable) -> str:
        """Format configuration options as a markdown table."""
        rows = []
        for opt in table.options:
            # Handle newlines in description for markdown table
            desc = opt.description.replace("\n", "<br>")
            rows.append([opt.name, opt.type, desc])

        return self.format_table(
            Table(
                headers=["Option", "Type", "Description"],
                rows=rows,
            )
        )

    def format_command_table(self, table: CommandTable) -> str:
        """Format commands as a markdown table."""
        rows = []
        for cmd in table.commands:
            desc = cmd.description.replace("\n", "<br>")
            rows.append([cmd.name, cmd.default_mapping or "--", desc])

        return self.format_table(
            Table(
                headers=["Command", "Default mapping", "Description"],
                rows=rows,
            )
        )

    def format_image(self, img: Image) -> str:
        """Format a simple markdown image."""
        md = f"![{img.alt}]({img.url})"
        if img.centered:
            return f'<p align="center">\n  {md}\n</p>'
        return md

    def format_responsive_image(self, img: ResponsiveImage) -> str:
        """Format a responsive image with dark/light mode variants."""
        picture = dedent(f'''
            <picture>
              <source media="(prefers-color-scheme: dark)" srcset="{img.dark_url}">
              <source media="(prefers-color-scheme: light)" srcset="{img.light_url}">
              <img alt="{img.alt}" src="{img.light_url}">
            </picture>
        ''').strip()
        if img.centered:
            return f'<p align="center">\n  {picture}\n</p>'
        return picture

    def format_badges(self, badges: Badges) -> str:
        """Format a row of badge images."""
        imgs = " ".join(f'<img src="{url}">' for url in badges.urls)
        if badges.centered:
            return f'<p align="center">\n  {imgs}\n</p>'
        return imgs

    def format_api_function(self, func: ApiFunction) -> str:
        """Format an API function for README."""
        lines = []

        # Function signature as code
        lines.append(f"`{func.signature}`")
        lines.append("")

        # Description
        desc = dedent(func.description).strip()
        lines.append(desc)

        # Parameters
        if func.params:
            lines.append("")
            lines.append("- **Parameters:**")
            for param in func.params:
                param_line = f"    - `{param.name}`: ({param.type}) {param.description}"
                lines.append(param_line)
                # Handle nested parameters
                for child in param.children:
                    child_line = f"        - `{child.name}`: ({child.type}) {child.description}"
                    lines.append(child_line)

        # Example code if provided
        if func.example:
            lines.append("")
            lines.append("```lua")
            lines.append(func.example)
            lines.append("```")

        return "\n".join(lines)




def build_documentation() -> List[Section]:
    """Build the complete documentation structure from YAML source files."""
    sections = load_sections_from_yaml()
    if sections is None:
        raise FileNotFoundError("scripts/docs/sections.yaml is required")
    return sections




# =============================================================================
# MAIN
# =============================================================================


def main():
    """Main function to generate documentation."""
    print("Building documentation structure...")
    docs = build_documentation()

    # Determine paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.dirname(script_dir)

    # Generate README
    print("Generating README.md...")
    readme_formatter = ReadmeFormatter()
    readme = readme_formatter.format_document(docs)

    readme_path = os.path.join(repo_root, "README.md")
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(readme)
    print(f"  Wrote {readme_path} ({len(readme)} bytes)")

    # Generate vimdoc
    print("Generating doc/mkdnflow.txt...")
    vimdoc_formatter = VimdocFormatter()
    vimdoc = vimdoc_formatter.format_document(docs)

    vimdoc_path = os.path.join(repo_root, "doc", "mkdnflow.txt")
    os.makedirs(os.path.dirname(vimdoc_path), exist_ok=True)
    with open(vimdoc_path, "w", encoding="utf-8") as f:
        f.write(vimdoc)
    print(f"  Wrote {vimdoc_path} ({len(vimdoc)} bytes)")

    print("Done!")


if __name__ == "__main__":
    main()
