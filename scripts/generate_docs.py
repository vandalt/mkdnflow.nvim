#!/usr/bin/env python3
"""
generate_docs.py - Documentation generator for Mkdnflow

This script is the SINGLE SOURCE OF TRUTH for Mkdnflow documentation.
It generates both outputs from structured Python data:
  - README.md (GitHub-flavored markdown)
  - doc/mkdnflow.txt (Vim help file)

Usage:
  python3 scripts/generate_docs.py
  # or
  make docs

The documentation is defined using content primitives (Prose, CodeBlock,
BulletList, Table, etc.) and Section structures. Two formatters handle
the output: ReadmeFormatter for markdown and VimdocFormatter for vim help.

To update documentation:
  1. Edit the content in build_documentation() or the data structures
  2. Run this script to regenerate both outputs
  3. Commit the changes to generate_docs.py AND the generated files

Author: Jake W. Vincent
"""

from __future__ import annotations
from dataclasses import dataclass, field
from typing import List, Optional, Union
from textwrap import wrap, dedent, indent
from abc import ABC, abstractmethod
import os
import re
import sys

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
# CONFIG OPTIONS DATA (migrated from CSV files)
# =============================================================================

MODULES_OPTIONS = [
    ConfigOption(
        name='`modules.bib`',
        type='`boolean`',
        description="""**`true`** (default): `bib` module is enabled (required for parsing `.bib` files and following citations).
`false`: Disable `bib` module functionality.""",
    ),
    ConfigOption(
        name='`modules.buffers`',
        type='`boolean`',
        description="""**`true`** (default): `buffers` module is enabled (required for backward and forward navigation through buffers).
`false`: Disable `buffers` module functionality.""",
    ),
    ConfigOption(
        name='`modules.conceal`',
        type='`boolean`',
        description="""**`true`** (default): `conceal` module is enabled (required if you wish to enable link concealing. This does not automatically enable conceal behavior; see `links.conceal`.)
`false`: Disable `conceal` module functionality.""",
    ),
    ConfigOption(
        name='`modules.cursor`',
        type='`boolean`',
        description="""**`true`** (default): `cursor` module is enabled (required for cursor movements: jumping to links, headings, etc.).
`false`: Disable `cursor` module functionality.""",
    ),
    ConfigOption(
        name='`modules.folds`',
        type='`boolean`',
        description="""**`true`** (default): `folds` module is enabled (required for section folding).
`false`: Disable `folds` module functionality.""",
    ),
    ConfigOption(
        name='`modules.foldtext`',
        type='`boolean`',
        description="""**`true`** (default): `foldtext` module is enabled (required for prettified foldtext).
`false`: Disable `foldtext` module functionality.""",
    ),
    ConfigOption(
        name='`modules.links`',
        type='`boolean`',
        description="""**`true`** (default): `links` module is enabled (required for creating, destroying, and following links).
`false`: Disable `links` module functionality.""",
    ),
    ConfigOption(
        name='`modules.lists`',
        type='`boolean`',
        description="""**`true`** (default): `lists` module is enabled (required for working in and manipulating lists, etc.).
`false`: Disable `lists` module functionality.""",
    ),
    ConfigOption(
        name='`modules.to_do`',
        type='`boolean`',
        description="""**`true`** (default): `to_do` module is enabled (required for manipulating to-do statuses/lists, toggling to-do items, to-do list sorting, etc.)
`false`: Disable `to_do` module functionality.""",
    ),
    ConfigOption(
        name='`modules.paths`',
        type='`boolean`',
        description="""**`true`** (default): `paths` module is enabled (required for link interpretation, link following, etc.).
`false`: Disable `paths` module functionality.""",
    ),
    ConfigOption(
        name='`modules.tables`',
        type='`boolean`',
        description="""**`true`** (default): `tables` module is enabled (required for table management, navigation, formatting, etc.).
`false`: Disable `tables` module functionality.""",
    ),
    ConfigOption(
        name='`modules.yaml`',
        type='`boolean`',
        description="""`true`: `yaml` module is enabled (required for parsing yaml headers).
**`false`** (default): Disable `yaml` module functionality.""",
    ),
    ConfigOption(
        name='`modules.cmp`',
        type='`boolean`',
        description="""`true`: `cmp` module is enabled (required if you wish to enable completion for `nvim-cmp`).
**`false`** (default): Disable `cmp` module functionality.""",
    ),
]

CREATE_DIRS_OPTIONS = [
    ConfigOption(
        name='`create_dirs`',
        type='`boolean`',
        description="""**`true`** (default): Directories referenced in a link will be (recursively) created if they do not exist.
`false`: No action will be taken when directories referenced in a link do not exist. Neovim will open a new file, but you will get an error when you attempt to write the file.""",
    ),
]

PERSPECTIVE_OPTIONS = [
    ConfigOption(
        name='`perspective.priority`',
        type='`string`',
        description="""**`'first'`** (default): Links will be interpreted relative to the first-opened file (when the current instance of Neovim was started).
`'current'`: Links will always be interpreted relative to the current file.
`'root'`: Links will be always interpreted relative to the root directory of the current notebook (requires `perspective.root_tell` to be specified).""",
    ),
    ConfigOption(
        name='`perspective.fallback`',
        type='`string`',
        description="""`'first'`: (see above)
**`'current'`** (default): (see above)
`'root'`: (see above)""",
    ),
    ConfigOption(
        name='`perspective.root_tell`',
        type='`string` | `boolean`',
        description="""**`false`** (default): The plugin does not look for the notebook root.
`string`: The name of a file (not a full path) by which a notebook's root directory can be identified. For instance, `'.root'` or `'index.md'`.""",
    ),
    ConfigOption(
        name='`perspective.nvim_wd_heel`',
        type='`boolean`',
        description="""`true`: Changes in perspective will be reflected in the nvim working directory. (In other words, the working directory will "heel" to the plugin's perspective.) This helps ensure (at least) that path completions (if using a completion plugin with support for paths) will be accurate and usable.
**`false`** (default): Neovim's working directory will not be affected by Mkdnflow.""",
    ),
    ConfigOption(
        name='`perspective.update`',
        type='`boolean`',
        description="""`true`: Perspective will be updated when following a link to a file in a separate notebook/wiki (or navigating backwards to a file in another notebook/wiki).
**`false`** (default): Perspective will be not updated when following a link to a file in a separate notebook/wiki. (Links in the file in the separate notebook/wiki will be interpreted relative to the original notebook/wiki.)""",
    ),
]

FILETYPES_OPTIONS = [
    ConfigOption(
        name='`filetypes.md`',
        type='`boolean`',
        description="""**`true`** (default): The plugin activates for files with a `.md` extension.
`false`: The plugin does not activate for files with a `.md` extension.""",
    ),
    ConfigOption(
        name='`filetypes.rmd`',
        type='`boolean`',
        description="""**`true`** (default): The plugin activates for files with a `.rmd` (rmarkdown) extension.
`false`: The plugin does not activate for files with a `.rmd` extension.""",
    ),
    ConfigOption(
        name='`filetypes.markdown`',
        type='`boolean`',
        description="""**`true`** (default): The plugin activates for files with a `.markdown` extension.
`false`: The plugin does not activate for files with a `.markdown` extension.""",
    ),
    ConfigOption(
        name='`filetypes.<ext>`',
        type='`boolean`',
        description="""`true`: The plugin activates for files with the specified extension.
`false`: The plugin does not activate for files with the specified extension.""",
    ),
]

WRAP_OPTIONS = [
    ConfigOption(
        name='`wrap`',
        type='`boolean`',
        description="""`true`: When jumping to next/previous links or headings, the cursor will continue searching at the beginning/end of the file.
**`false`** (default): When jumping to next/previous links or headings, the cursor will stop searching at the end/beginning of the file.""",
    ),
]

BIB_OPTIONS = [
    ConfigOption(
        name='`bib.default_path`',
        type='`string` | `nil`',
        description="""**`nil`** (default): No default/fallback bib file will be used to search for citation keys.
`string`: A path to a default .bib file to look for citation keys in when attempting to follow a reference. The path need not be in the root directory of the notebook.""",
    ),
    ConfigOption(
        name='`bib.find_in_root`',
        type='`boolean`',
        description="""**`true`** (default): When `perspective.priority` is also set to `root` (and a root directory was found), the plugin will search for bib files to reference in the notebook's top-level directory. If `bib.default_path` is also specified, the default path will be added to the list of bib files found in the top-level directory so that it will also be searched.
`false`: The notebook's root directory will not be searched for bib files.""",
    ),
]

SILENT_OPTIONS = [
    ConfigOption(
        name='`silent`',
        type='`boolean`',
        description="""`true`: The plugin will not display any messages in the console except compatibility warnings related to your config.
**`false`** (default): The plugin will display messages to the console.""",
    ),
]

CURSOR_OPTIONS = [
    ConfigOption(
        name='`cursor.jump_patterns`',
        type='`table` | `nil`',
        description="""**`nil`** (default): The default jump patterns for the configured link style are used (markdown-style links by default).
`table`: A table of custom Lua regex patterns.
`{}` (empty table): Disable link jumping without disabling the `cursor` module.""",
    ),
]

LINKS_OPTIONS = [
    ConfigOption(
        name='`links.style`',
        type='`string`',
        description="""**`'markdown'`** (default): Links will be expected in the standard markdown format: `[<title>](<source>)`
`'wiki'`: Links will be expected in the unofficial wiki-link style, specifically the title-after-pipe format: `[[<source>|<title>]]`.""",
    ),
    ConfigOption(
        name='`links.name_is_source`',
        type='`boolean`',
        description="""`true`: Wiki-style links will be created with the source and name being the same (e.g. `[[Link]]` will display as "Link" and go to a file named "Link.md").
**`false`** (default): Wiki-style links will be created with separate name and source (e.g. `[[link-to-source|Link]]` will display as "Link" and go to a file named "link-to-source.md").""",
    ),
    ConfigOption(
        name='`links.conceal`',
        type='`boolean`',
        description="""`true`: Link sources and delimiters will be concealed (depending on which link style is selected).
**`false`** (default): Link sources and delimiters will not be concealed by mkdnflow.""",
    ),
    ConfigOption(
        name='`links.context`',
        type='`integer`',
        description="""When following or jumping to links, consider `n` lines before and after a given line (useful if you ever permit links to be interrupted by a hard line break). Default: **`0`**.""",
    ),
    ConfigOption(
        name='`links.implicit_extension`',
        type='`string`',
        description="""A string that instructs the plugin (a) how to interpret links to files that do not have an extension, and (b) how to create new links from the word under cursor or text selection.

**`nil`** (default): Extensions will be explicit when a link is created and must be explicit in any notebook link.
`'<any extension>'` (e.g. `'md'`): Links without an extension (e.g. `[Homepage](index)`) will be interpreted with the implicit extension (e.g. `index.md`), and new links will be created without an extension.""",
    ),
    ConfigOption(
        name='`links.transform_explicit`',
        type='`fun(string): string` | `boolean`',
        description="""`false`: No transformations are applied to the text to be turned into the name of the link source/path.
**`fun(string): string`** (default): A function that transforms the text to be inserted as the source/path of a link when a link is created. Anchor links are not currently customizable. For an example, see the sample recipes beneath this table.""",
    ),
    ConfigOption(
        name='`links.transform_implicit`',
        type='`fun(string): string` | `boolean`',
        description="""**`false`** (default): Do not perform any implicit transformations on the link's source.
`fun(string): string`: A function that transforms the path of a link immediately before interpretation. It does not transform the actual text in the buffer but can be used to modify link interpretation. For an example, see the sample recipe below.""",
    ),
    ConfigOption(
        name='`links.create_on_follow_failure`',
        type='`boolean`',
        description="""**`true`** (default): Try to create a link from the word under the cursor if there is no link under the cursor to follow.
`false`: Do nothing if trying to follow a link and a link can't be found under the cursor.""",
    ),
]

NEW_FILE_TEMPLATE_OPTIONS = [
    ConfigOption(
        name='`new_file_template.use_template`',
        type='`boolean`',
        description="""`true`: Use the new-file template when opening a new file by following a link.
**`false`** (default): Don't use the new-file template when opening a new file by following a link.""",
    ),
    ConfigOption(
        name='`new_file_template.placeholders.before`',
        type='`table<string, string|fun(): string>`',
        description="""A table whose keys are placeholder names mapped either to a function (to be evaluated immediately before the buffer is opened in the current window) or to one of a limited set of recognized strings:

`'link_title'`: The title of the link that was followed to get to the just-opened file.
`'os_date'`: The current date, according to the OS.

Default: `{ title = 'link_title', date = 'os_date' }`""",
    ),
    ConfigOption(
        name='`new_file_template.placeholders.after`',
        type='`table<string, string|fun(): string>`',
        description="""A table whose keys are placeholder names mapped either to a function (to be evaluated immediately after the buffer is opened in the current window) or to one of a limited set of recognized strings (see above). Default: `{}`""",
    ),
    ConfigOption(
        name='`new_file_template.template`',
        type='`string`',
        description="""A string, optionally containing placeholder names, that will be inserted into a new file. Default: `'# {{ title }}'`""",
    ),
]

TO_DO_OPTIONS = [
    ConfigOption(
        name='`to_do.highlight`',
        type='`boolean`',
        description="""`true`: Apply highlighting to to-do status markers and/or content (as defined in `to_do.statuses[*].highlight`).
**`false`** (default): Do not apply any highlighting.""",
    ),
    ConfigOption(
        name='`to_do.status_propagation.up`',
        type='`boolean`',
        description="""**`true`** (default): Update ancestor statuses (recursively) when a descendant status is changed. Updated according to logic provided in `to_do.statuses[*].propagate.up`.
`false`: Ancestor statuses are not affected by descendant status changes.""",
    ),
    ConfigOption(
        name='`to_do.status_propagation.down`',
        type='`boolean`',
        description="""**`true`** (default): Update descendant statuses (recursively) when an ancestor's status is changed. Updated according to logic provided in `to_do.statuses[*].propagate.down`.
`false`: Descendant statuses are not affected by ancestor status changes.""",
    ),
    ConfigOption(
        name='`to_do.sort_on_status_change`',
        type='`boolean`',
        description="""`true`: Sort a to-do list when an item's status is changed.
**`false`** (default): Leave all to-do items in their current position when an item's status is changed.
Note: This will not apply if the to-do item's status is changed manually (i.e. by typing or pasting in the status marker).""",
    ),
    ConfigOption(
        name='`to_do.sort.recursive`',
        type='`boolean`',
        description="""`true`: `sort_on_status_change` applies recursively, sorting the host list of each successive parent until the root of the list is reached.
**`false`** (default): `sort_on_status_change` only applies at the current to-do list level (not to the host list of the parent to-do item).""",
    ),
    ConfigOption(
        name='`to_do.sort.cursor_behavior.track`',
        type='`boolean`',
        description="""**`true`** (default): Move the cursor so that it remains on the same to-do item, even after a to-do list sort relocates the item.
`false`: The cursor remains on its current line number, even if the to-do item is relocated by sorting.""",
    ),
    ConfigOption(
        name='`to_do.statuses`',
        type='`table` (array-like)',
        description="""A list of tables, each of which represents a to-do status. See options in the following rows. An arbitrary number of to-do status tables can be provided. See default statuses in the settings table.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].name`',
        type='`string`',
        description="""The designated name of the to-do status.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].marker`',
        type='`string` | `table`',
        description="""The marker symbol to use for the status. The marker's string width must be 1.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].highlight.marker`',
        type='`table` (highlight definition)',
        description="""A table of highlight definitions to apply to a status marker, including brackets. See the `{val}` parameter of `:h nvim_set_hl` for possible options.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].highlight.content`',
        type='`table` (highlight definition)',
        description="""A table of highlight definitions to apply to the to-do item content (everything following the status marker). See the `{val}` parameter of `:h nvim_set_hl` for possible options.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].exclude_from_rotation`',
        type='`boolean`',
        description="""`true`: When toggling/rotating a to-do item's status, exclude the current symbol from the list of symbols used.
`false`: Leave the symbol in the rotation.
Note: This setting is useful if there is a status marker that you never want to manually set and only want to apply when automatically updating ancestors or descendants.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].sort.section`',
        type='`integer`',
        description="""The integer should represent the linear section of the list in which items of this status should be placed when sorted. A section refers to a segment of a to-do list. If you want items with the `'in_progress'` status to be first in the list, you would set this option to `1` for the status.
Note: Sections are not visually delineated in any way other than items with the same section number occurring on adjacent lines in the list.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].sort.position`',
        type='`string`',
        description="""Where in its assigned section a to-do item should be placed:
`'top'`: Place a sorted item at the top of its corresponding section.
`'bottom'`: Place a sorted item at the bottom of its corresponding section.
`'relative'`: Maintain the current relative order of the sorted item whose status was just changed (vs. other list items).""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].propagate.up`',
        type='`fun(to_do_list): string` | `nil`',
        description="""A function that accepts a to-do list instance and returns a valid to-do status name. The list passed in is the list that hosts the to-do item whose status was just changed. The return value should be the desired value of the parent. Return `nil` to leave the parent's status as is.""",
    ),
    ConfigOption(
        name='`to_do.statuses[*].propagate.down`',
        type='`fun(to_do_list): string[]`',
        description="""A function that accepts a to-do list instance and returns a list of valid to-do status names. The list passed in will be the child list of the to-do item whose status was just changed. Return `nil` or an empty table to leave the children's status as is.""",
    ),
]

FOLDTEXT_OPTIONS = [
    ConfigOption(
        name='`foldtext.object_count`',
        type='`boolean`',
        description="""**`true`** (default): Show a count of all objects inside of a folded section.
`false`: Do not show a count of any objects inside of a folded section.""",
    ),
    ConfigOption(
        name='`foldtext.object_count_icon_set`',
        type='`string` | `table`',
        description="""**`'emoji'`** (default): Use pre-defined emojis as icons for counted objects.
`'plain'`: Use pre-defined plaintext UTF-8 characters as icons for counted objects.
`'nerdfont'`: Use pre-defined nerdfont characters as icons for counted objects. Requires a nerdfont.
`table<string, string>`: Use custom mapping of object names to icons.""",
    ),
    ConfigOption(
        name='`foldtext.object_count_opts`',
        type='`fun(): table<string, table>`',
        description="""A function that returns the options table defining the final attributes of the objects to be counted, including icons and counting methods. The pre-defined object types are `tbl`, `ul`, `ol`, `todo`, `img`, `fncblk`, `sec`, `par`, and `link`.""",
    ),
    ConfigOption(
        name='`foldtext.line_count`',
        type='`boolean`',
        description="""**`true`** (default): Show a count of the lines contained in the folded section.
`false`: Don't show a line count.""",
    ),
    ConfigOption(
        name='`foldtext.line_percentage`',
        type='`boolean`',
        description="""**`true`** (default): Show the percentage of document (buffer) lines contained in the folded section.
`false`: Don't show the percentage.""",
    ),
    ConfigOption(
        name='`foldtext.word_count`',
        type='`boolean`',
        description="""`true`: Show a count of the paragraph words in the folded section, ignoring words inside of other objects.
**`false`** (default): Don't show a word count.""",
    ),
    ConfigOption(
        name='`foldtext.title_transformer`',
        type='`fun(): fun(string): string`',
        description="""A function that returns another function. The inner function accepts a string (the section heading text) and returns a potentially modified string.""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.left_edge`',
        type='`string`',
        description="""The character(s) to use at the very left edge of the foldtext. Default: `'⢾⣿⣿'`.""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.right_edge`',
        type='`string`',
        description="""The character(s) to use at the very right edge of the foldtext. Default: `'⣿⣿⡷'`""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.item_separator`',
        type='`string`',
        description="""The character(s) used to separate the items within a section. Default: `' · '`""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.section_separator`',
        type='`string`',
        description="""The character(s) used to separate adjacent sections. Default: `' ⣹⣿⣏ '`""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.left_inside`',
        type='`string`',
        description="""The character(s) used at the internal left edge of fill characters. Default: `' ⣹'`""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.right_inside`',
        type='`string`',
        description="""The character(s) used at the internal right edge of fill characters. Default: `'⣏ '`""",
    ),
    ConfigOption(
        name='`foldtext.fill_chars.middle`',
        type='`string`',
        description="""The character used to fill empty space in the foldtext line. Default: `'⣿'`""",
    ),
]

TABLES_OPTIONS = [
    ConfigOption(
        name='`tables.trim_whitespace`',
        type='`boolean`',
        description="""**`true`** (default): Trim extra whitespace from the end of a table cell when a table is formatted.
`false`: Leave whitespace at the end of a table cell when formatting.""",
    ),
    ConfigOption(
        name='`tables.format_on_move`',
        type='`boolean`',
        description="""**`true`** (default): Format the table each time the cursor is moved to the next/previous cell/row using the plugin's API.
`false`: Don't format the table when the cursor is moved.""",
    ),
    ConfigOption(
        name='`tables.auto_extend_rows`',
        type='`boolean`',
        description="""`true`: Add another row when attempting to jump to the next row and the row doesn't exist.
**`false`** (default): Leave the table when attempting to jump to the next row and the row doesn't exist.""",
    ),
    ConfigOption(
        name='`tables.auto_extend_cols`',
        type='`boolean`',
        description="""`true`: Add another column when attempting to jump to the next column and the column doesn't exist.
**`false`** (default): Go to the first cell of the next row when attempting to jump to the next column and the column doesn't exist.""",
    ),
    ConfigOption(
        name='`tables.style.cell_padding`',
        type='`integer`',
        description="""**`1`** (default): Use one space as padding at the beginning and end of each cell.
`<n>`: Use `<n>` spaces as cell padding.""",
    ),
    ConfigOption(
        name='`tables.style.separator_padding`',
        type='`integer`',
        description="""**`1`** (default): Use one space as padding in the separator row.
`<n>`: Use `<n>` spaces as padding in the separator row.""",
    ),
    ConfigOption(
        name='`tables.style.outer_pipes`',
        type='`boolean`',
        description="""**`true`** (default): Include outer pipes when formatting a table.
`false`: Do not use outer pipes when formatting a table.""",
    ),
    ConfigOption(
        name='`tables.style.mimic_alignment`',
        type='`boolean`',
        description="""**`true`** (default): Mimic the cell alignment indicated in the separator row when formatting the table.
`false`: Always visually left-align cell contents when formatting a table.""",
    ),
]

YAML_OPTIONS = [
    ConfigOption(
        name='`yaml.bib.override`',
        type='`boolean`',
        description="""`true`: A bib path specified in a markdown file's yaml header should be the only source considered for bib references in that file.
**`false`** (default): All known bib paths will be considered, whether specified in the yaml header or in your configuration settings.""",
    ),
]

MAPPINGS_OPTIONS = [
    ConfigOption(
        name='`mappings.<command>`',
        type='`[string|string[], string]`',
        description="""The first item is a string or an array of strings representing the mode(s) that the mapping should apply in (`'n'`, `'v'`, etc.). The second item is a string representing the mapping (in the expected format for vim).""",
    ),
]

# =============================================================================
# COMMANDS DATA
# =============================================================================

COMMANDS = [
    Command(
        name='`MkdnEnter`',
        default_mapping='--',
        description="""Triggers a wrapper function which will (a) infer your editor mode, and then if in normal or visual mode, either follow a link, create a new link from the word under the cursor or visual selection, or fold a section (if cursor is on a section heading); if in insert mode, it will create a new list item (if cursor is in a list), go to the next row in a table (if cursor is in a table), or behave normally (if cursor is not in a list or a table).

Note: There is no insert-mode mapping for this command by default since some may find its effects intrusive. To enable the insert-mode functionality, add to the mappings table: `MkdnEnter = {{'i', 'n', 'v'}, '<CR>'}`.""",
    ),
    Command(
        name='`MkdnNextLink`',
        default_mapping="`{ 'n', '<Tab>' }`",
        description="""Move cursor to the beginning of the next link (if there is a next link).""",
    ),
    Command(
        name='`MkdnPrevLink`',
        default_mapping="`{ 'n', '<S-Tab>' }`",
        description="""Move the cursor to the beginning of the previous link (if there is one).""",
    ),
    Command(
        name='`MkdnNextHeading`',
        default_mapping="`{ 'n', ']]' }`",
        description="""Move the cursor to the beginning of the next heading (if there is one).""",
    ),
    Command(
        name='`MkdnPrevHeading`',
        default_mapping="`{ 'n', '[[' }`",
        description="""Move the cursor to the beginning of the previous heading (if there is one).""",
    ),
    Command(
        name='`MkdnGoBack`',
        default_mapping="`{ 'n', '<BS>' }`",
        description="""Open the historically last-active buffer in the current window.

Note: The back-end function for `:MkdnGoBack` (`require('mkdnflow').buffers.goBack()`) returns a boolean indicating the success of `goBack()`. This may be useful if you wish to remap `<BS>` such that when `goBack()` is unsuccessful, another function is performed.""",
    ),
    Command(
        name='`MkdnGoForward`',
        default_mapping="`{ 'n', '<Del>' }`",
        description="""Open the buffer that was historically navigated away from in the current window.""",
    ),
    Command(
        name='`MkdnCreateLink`',
        default_mapping='--',
        description="""Create a link from the word under the cursor (in normal mode) or from the visual selection (in visual mode).""",
    ),
    Command(
        name='`MkdnCreateLinkFromClipboard`',
        default_mapping="`{ { 'n', 'v' }, '<leader>p' }`",
        description="""Create a link, using the content from the system clipboard (e.g. a URL) as the source and the word under cursor or visual selection as the link text.""",
    ),
    Command(
        name='`MkdnFollowLink`',
        default_mapping='--',
        description="""Open the link under the cursor, creating missing directories if desired, or if there is no link under the cursor, make a link from the word under the cursor. Image links (`![alt](path)`) are opened in the system's default viewer.""",
    ),
    Command(
        name='`MkdnDestroyLink`',
        default_mapping="`{ 'n', '<M-CR>' }`",
        description="""Destroy the link under the cursor, replacing it with just the text from the link name.""",
    ),
    Command(
        name='`MkdnTagSpan`',
        default_mapping="`{ 'v', '<M-CR>' }`",
        description="""Tag a visually-selected span of text with an ID, allowing it to be linked to with an anchor link.""",
    ),
    Command(
        name='`MkdnMoveSource`',
        default_mapping="`{ 'n', '<F2>' }`",
        description="""Open a dialog where you can provide a new source for a link and the plugin will rename and move the associated file on the backend (and rename the link source).""",
    ),
    Command(
        name='`MkdnYankAnchorLink`',
        default_mapping="`{ 'n', 'yaa' }`",
        description="""Yank a formatted anchor link (if cursor is currently on a line with a heading).""",
    ),
    Command(
        name='`MkdnYankFileAnchorLink`',
        default_mapping="`{ 'n', 'yfa' }`",
        description="""Yank a formatted anchor link with the filename included before the anchor (if cursor is currently on a line with a heading).""",
    ),
    Command(
        name='`MkdnIncreaseHeading`',
        default_mapping="`{ 'n', '+' }`",
        description="""Increase heading importance (remove hashes).""",
    ),
    Command(
        name='`MkdnDecreaseHeading`',
        default_mapping="`{ 'n', '-' }`",
        description="""Decrease heading importance (add hashes).""",
    ),
    Command(
        name='`MkdnToggleToDo`',
        default_mapping="`{ { 'n', 'v' }, '<C-Space>' }`",
        description="""Toggle to-do list item's completion status or convert a list item into a to-do list item.""",
    ),
    Command(
        name='`MkdnUpdateNumbering`',
        default_mapping="`{ 'n', '<leader>nn' }`",
        description="""Update numbering for all siblings of the list item of the current line.""",
    ),
    Command(
        name='`MkdnNewListItem`',
        default_mapping='--',
        description="""Add a new ordered list item, unordered list item, or (uncompleted) to-do list item.""",
    ),
    Command(
        name='`MkdnNewListItemBelowInsert`',
        default_mapping="`{ 'n', 'o' }`",
        description="""Add a new list item below the current line and begin insert mode. Add a new line and enter insert mode when the cursor is not in a list.""",
    ),
    Command(
        name='`MkdnNewListItemAboveInsert`',
        default_mapping="`{ 'n', 'O' }`",
        description="""Add a new list item above the current line and begin insert mode. Add a new line and enter insert mode when the cursor is not in a list.""",
    ),
    Command(
        name='`MkdnExtendList`',
        default_mapping='--',
        description="""Like above, but the cursor stays on the current line (new list items of the same type are added below).""",
    ),
    Command(
        name='`MkdnTable ncol nrow (noh)`',
        default_mapping='--',
        description="""Make a table of `ncol` columns and `nrow` rows. Pass `noh` as a third argument to exclude table headers.""",
    ),
    Command(
        name='`MkdnTableFormat`',
        default_mapping='--',
        description="""Format a table under the cursor.""",
    ),
    Command(
        name='`MkdnTableNextCell`',
        default_mapping="`{ 'i', '<Tab>' }`",
        description="""Move the cursor to the beginning of the next cell in the table, jumping to the next row if needed.""",
    ),
    Command(
        name='`MkdnTablePrevCell`',
        default_mapping="`{ 'i', '<S-Tab>' }`",
        description="""Move the cursor to the beginning of the previous cell in the table, jumping to the previous row if needed.""",
    ),
    Command(
        name='`MkdnTableNextRow`',
        default_mapping='--',
        description="""Move the cursor to the beginning of the same cell in the next row of the table.""",
    ),
    Command(
        name='`MkdnTablePrevRow`',
        default_mapping="`{ 'i', '<M-CR>' }`",
        description="""Move the cursor to the beginning of the same cell in the previous row of the table.""",
    ),
    Command(
        name='`MkdnTableNewRowBelow`',
        default_mapping="`{ 'n', '<leader>ir' }`",
        description="""Add a new row below the row the cursor is currently in.""",
    ),
    Command(
        name='`MkdnTableNewRowAbove`',
        default_mapping="`{ 'n', '<leader>iR' }`",
        description="""Add a new row above the row the cursor is currently in.""",
    ),
    Command(
        name='`MkdnTableNewColAfter`',
        default_mapping="`{ 'n', '<leader>ic' }`",
        description="""Add a new column following the column the cursor is currently in.""",
    ),
    Command(
        name='`MkdnTableNewColBefore`',
        default_mapping="`{ 'n', '<leader>iC' }`",
        description="""Add a new column before the column the cursor is currently in.""",
    ),
    Command(
        name='`MkdnTab`',
        default_mapping='--',
        description="""Wrapper function which will jump to the next cell in a table (if cursor is in a table) or indent an (empty) list item (if cursor is in a list item).""",
    ),
    Command(
        name='`MkdnSTab`',
        default_mapping='--',
        description="""Wrapper function which will jump to the previous cell in a table (if cursor is in a table) or de-indent an (empty) list item (if cursor is in a list item).""",
    ),
    Command(
        name='`MkdnFoldSection`',
        default_mapping="`{ 'n', '<leader>f' }`",
        description="""Fold the section the cursor is currently on/in.""",
    ),
    Command(
        name='`MkdnUnfoldSection`',
        default_mapping="`{ 'n', '<leader>F' }`",
        description="""Unfold the folded section the cursor is currently on.""",
    ),
    Command(
        name='`Mkdnflow`',
        default_mapping='--',
        description="""Manually start Mkdnflow.""",
    ),
]


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
            self.right_align("MKDNFLOW.NVIM REFERENCE", "*Mkdnflow.nvim*"),
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


# =============================================================================
# DOCUMENTATION CONTENT
# =============================================================================

# Default config code block (shared between README and vimdoc)
DEFAULT_CONFIG = """\
{
    modules = {
        bib = true,
        buffers = true,
        conceal = true,
        cursor = true,
        folds = true,
        foldtext = true,
        links = true,
        lists = true,
        maps = true,
        paths = true,
        tables = true,
        to_do = true,
        yaml = false,
        cmp = false,
    },
    create_dirs = true,
    silent = false,
    wrap = false,
    perspective = {
        priority = 'first',
        fallback = 'current',
        root_tell = false,
        nvim_wd_heel = false,
        update = true,
    },
    filetypes = {
        md = true,
        rmd = true,
        markdown = true,
    },
    foldtext = {
        object_count = true,
        object_count_icon_set = 'emoji',
        object_count_opts = function()
            return require('mkdnflow').foldtext.default_count_opts
        end,
        line_count = true,
        line_percentage = true,
        word_count = false,
        title_transformer = function()
            return require('mkdnflow').foldtext.default_title_transformer
        end,
        fill_chars = {
            left_edge = '⢾⣿⣿',
            right_edge = '⣿⣿⡷',
            item_separator = ' · ',
            section_separator = ' ⣹⣿⣏ ',
            left_inside = ' ⣹',
            right_inside = '⣏ ',
            middle = '⣿',
        },
    },
    bib = {
        default_path = nil,
        find_in_root = true,
    },
    cursor = {
        jump_patterns = nil,
    },
    links = {
        style = 'markdown',
        name_is_source = false,
        conceal = false,
        context = 0,
        implicit_extension = nil,
        transform_implicit = false,
        transform_explicit = function(text)
            text = text:gsub('[ /]', '-')
            text = text:lower()
            text = os.date('%Y-%m-%d_') .. text
            return text
        end,
        create_on_follow_failure = true,
    },
    new_file_template = {
        use_template = false,
        placeholders = {
            before = {
                title = 'link_title',
                date = 'os_date',
            },
            after = {},
        },
        template = '# {{ title }}',
    },
    to_do = {
        highlight = false,
        statuses = {
            {
                name = 'not_started',
                symbol = ' ',
                colors = {
                    marker = { link = 'Conceal' },
                    content = { link = 'Conceal' },
                },
                sort = { section = 2, position = 'top' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list) ... end,
                    down = function(child_list) ... end,
                },
            },
            {
                name = 'in_progress',
                symbol = '-',
                colors = {
                    marker = { link = 'WarningMsg' },
                    content = { bold = true },
                },
                sort = { section = 1, position = 'bottom' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list) ... end,
                    down = function(child_list) end,
                },
            },
            {
                name = 'complete',
                symbol = { 'X', 'x' },
                colors = {
                    marker = { link = 'String' },
                    content = { link = 'Conceal' },
                },
                sort = { section = 3, position = 'top' },
                exclude_from_rotation = false,
                propagate = {
                    up = function(host_list) ... end,
                    down = function(child_list) ... end,
                },
            },
        },
        status_propagation = {
            up = true,
            down = true,
        },
        sort = {
            on_status_change = false,
            recursive = false,
            cursor_behavior = {
                track = true,
            },
        },
    },
    tables = {
        trim_whitespace = true,
        format_on_move = true,
        auto_extend_rows = false,
        auto_extend_cols = false,
        style = {
            cell_padding = 1,
            separator_padding = 1,
            outer_pipes = true,
            mimic_alignment = true,
        },
    },
    yaml = {
        bib = { override = false },
    },
    mappings = {
        MkdnEnter = { { 'n', 'v' }, '<CR>' },
        MkdnGoBack = { 'n', '<BS>' },
        MkdnGoForward = { 'n', '<Del>' },
        MkdnMoveSource = { 'n', '<F2>' },
        MkdnNextLink = { 'n', '<Tab>' },
        MkdnPrevLink = { 'n', '<S-Tab>' },
        MkdnFollowLink = false,
        MkdnDestroyLink = { 'n', '<M-CR>' },
        MkdnTagSpan = { 'v', '<M-CR>' },
        MkdnYankAnchorLink = { 'n', 'yaa' },
        MkdnYankFileAnchorLink = { 'n', 'yfa' },
        MkdnNextHeading = { 'n', ']]' },
        MkdnPrevHeading = { 'n', '[[' },
        MkdnIncreaseHeading = { 'n', '+' },
        MkdnDecreaseHeading = { 'n', '-' },
        MkdnToggleToDo = { { 'n', 'v' }, '<C-Space>' },
        MkdnNewListItem = false,
        MkdnNewListItemBelowInsert = { 'n', 'o' },
        MkdnNewListItemAboveInsert = { 'n', 'O' },
        MkdnExtendList = false,
        MkdnUpdateNumbering = { 'n', '<leader>nn' },
        MkdnTableNextCell = { 'i', '<Tab>' },
        MkdnTablePrevCell = { 'i', '<S-Tab>' },
        MkdnTableNextRow = false,
        MkdnTablePrevRow = { 'i', '<M-CR>' },
        MkdnTableNewRowBelow = { 'n', '<leader>ir' },
        MkdnTableNewRowAbove = { 'n', '<leader>iR' },
        MkdnTableNewColAfter = { 'n', '<leader>ic' },
        MkdnTableNewColBefore = { 'n', '<leader>iC' },
        MkdnFoldSection = { 'n', '<leader>f' },
        MkdnUnfoldSection = { 'n', '<leader>F' },
        MkdnTab = false,
        MkdnSTab = false,
        MkdnCreateLink = false,
        MkdnCreateLinkFromClipboard = { { 'n', 'v' }, '<leader>p' },
    },
}"""


def build_documentation() -> List[Section]:
    """Build the complete documentation structure."""

    return [
        # =====================================================================
        # INTRODUCTION
        # =====================================================================
        Section(
            title="Introduction",
            tag="intro",
            emoji="🚀",
            content=[
                Prose(
                    """
                    Mkdnflow is designed for the *fluent* navigation and management of
                    [markdown](https://markdownguide.org) documents and document collections
                    (notebooks, wikis, etc). It features numerous convenience functions that
                    make it easier to work within raw markdown documents or document collections:
                    link and reference handling (see `link-handling`), navigation
                    (see `navigation`), table support (see `table-support`), list
                    (see `list-support`) and to-do list (see `todo-support`) support, file
                    management (see `file-mgmt`), section folding (see `folding`), and more.
                    Use it for notetaking, personal knowledge management, static website
                    building, and more. Most features are highly tweakable (see `configuration`).
                    """
                ),
            ],
        ),
        # =====================================================================
        # FEATURES
        # =====================================================================
        Section(
            title="Features",
            tag="features",
            emoji="✨",
            children=[
                Section(
                    title="Navigation",
                    tag="navigation",
                    emoji="🧭",
                    children=[
                        Section(
                            title="Within-buffer navigation",
                            tag="nav-buffer",
                            content=[
                                BulletList(
                                    items=[
                                        ListItem("Jump to links", done=True),
                                        ListItem("Jump to section headings", done=True),
                                    ]
                                ),
                                Image(
                                    url="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/gif/in_buffer_nav/in_buffer_nav.gif",
                                    alt="In-buffer navigation demo",
                                ),
                            ],
                        ),
                        Section(
                            title="Within-notebook navigation",
                            tag="nav-notebook",
                            content=[
                                BulletList(
                                    items=[
                                        ListItem(
                                            "Link following",
                                            done=True,
                                            children=[
                                                ListItem("Open markdown and other text filetypes in the current window", done=True),
                                                ListItem("Open other filetypes and URLs with your system's default application", done=True),
                                            ],
                                        ),
                                        ListItem("Browser-like 'Back' and 'Forward' functionality", done=True),
                                        ListItem("Table of contents window", done=False),
                                    ]
                                ),
                            ],
                        ),
                    ],
                ),
                Section(
                    title="Link and reference handling",
                    tag="link-handling",
                    emoji="🔗",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Link creation from a visual selection or the word under the cursor", done=True),
                                ListItem("Link destruction", done=True),
                                ListItem("Follow links to local paths and other Markdown files", done=True),
                                ListItem("Follow external links (open using default application)", done=True),
                                ListItem(
                                    "Follow `.bib`-based references",
                                    done=True,
                                    children=[
                                        ListItem("Open `url` or `doi` field in the default browser", done=True),
                                        ListItem("Open documents specified in `file` field", done=True),
                                    ],
                                ),
                                ListItem("Implicit filetype extensions", done=True),
                                ListItem(
                                    "Support for various link types",
                                    done=True,
                                    children=[
                                        ListItem("Standard Markdown links (`[my page](my_page.md)`)", done=True),
                                        ListItem("Wiki links (direct `[[my page]]` or piped `[[my_page.md|my page]]`)", done=True),
                                        ListItem("Automatic links (`<https://my.page>`)", done=True),
                                        ListItem("Reference-style links (`[my page][1]` with `[1]: my_page.md`)", done=True),
                                        ListItem("Image links (`![alt text](image.png)`) — opened in system viewer", done=True),
                                    ],
                                ),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="Table support",
                    tag="table-support",
                    emoji="📊",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Table creation", done=True),
                                ListItem("Table extension (add rows and columns)", done=True),
                                ListItem("Table formatting", done=True),
                                ListItem("Paste delimited data as a table", done=False),
                                ListItem("Import delimited file into a new table", done=False),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="List support",
                    tag="list-support",
                    emoji="📝",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Automatic list extension", done=True),
                                ListItem("Sensible auto-indentation and auto-dedentation", done=True),
                                ListItem("Ordered list number updating", done=True),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="To-do list support",
                    tag="todo-support",
                    emoji="✅",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Toggle to-do item status", done=True),
                                ListItem("Status propagation", done=True),
                                ListItem("To-do list sorting", done=True),
                                ListItem("Create to-do items from plain ordered or unordered list items", done=True),
                                ListItem("Customizable highlighting for to-do status markers and content", done=True),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="File management",
                    tag="file-mgmt",
                    emoji="📁",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Simultaneous link and file renaming", done=True),
                                ListItem("As-needed directory creation", done=True),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="Folding",
                    tag="folding",
                    emoji="🪗",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Section folding and fold toggling", done=True),
                                ListItem(
                                    "Helpful indicators for folded section contents",
                                    done=True,
                                    children=[
                                        ListItem("Section heading level", done=True),
                                        ListItem("Counts of Markdown objects (tables, lists, code blocks, etc.)", done=True),
                                        ListItem("Line and word counts", done=True),
                                    ],
                                ),
                                ListItem("YAML block folding", done=False),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="Completion",
                    tag="completion",
                    emoji="🔮",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Path completion", done=True),
                                ListItem("Completion of bibliography items", done=True),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="YAML block parsing",
                    tag="yaml-parsing",
                    emoji="🧩",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Specify a bibliography file in YAML front matter", done=True),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="Visual enhancements",
                    tag="visual",
                    emoji="🖌️",
                    content=[
                        BulletList(
                            items=[
                                ListItem("Conceal markdown and wiki link syntax", done=True),
                                ListItem(
                                    "Extended link highlighting",
                                    done=False,
                                    children=[
                                        ListItem("Automatic links", done=False),
                                        ListItem("Wiki links", done=False),
                                    ],
                                ),
                            ]
                        ),
                    ],
                ),
            ],
        ),
        # =====================================================================
        # INSTALLATION
        # =====================================================================
        Section(
            title="Installation",
            tag="installation",
            emoji="💾",
            content=[
                Prose(
                    """
                    **Requirements**:

                    * Linux, macOS, or Windows
                    * Neovim >= 0.10.0 (older versions may work, but the plugin is only tested on Neovim 0.10.x)

                    Install Mkdnflow using your preferred package manager for Neovim. Once installed,
                    Mkdnflow is configured and initialized using a setup function.
                    """
                ),
                Collapsible(
                    summary="Install with Lazy",
                    content=[
                        CodeBlock(
                            """\
                            require('lazy').setup({
                                -- Your other plugins
                                {
                                    'jakewvincent/mkdnflow.nvim',
                                    config = function()
                                        require('mkdnflow').setup({
                                            -- Your config
                                        })
                                    end
                                }
                                -- Your other plugins
                            })"""
                        ),
                    ],
                ),
                Collapsible(
                    summary="Install with Vim-Plug",
                    content=[
                        CodeBlock(
                            """\
                            " Vim-Plug
                            Plug 'jakewvincent/mkdnflow.nvim'

                            " Include the setup function somewhere else in your init.vim file, or the
                            " plugin won't activate itself:
                            lua << EOF
                            require('mkdnflow').setup({
                                -- Config goes here; leave blank for defaults
                            })
                            EOF""",
                            language="vim",
                        ),
                    ],
                ),
            ],
        ),
        # =====================================================================
        # CONFIGURATION
        # =====================================================================
        Section(
            title="Configuration",
            tag="configuration",
            emoji="⚙️",
            children=[
                Section(
                    title="Quick start",
                    tag="quickstart",
                    emoji="⚡",
                    content=[
                        Prose(
                            """
                            Mkdnflow is configured and initialized using a setup function. To use
                            the default settings, pass no arguments or an empty table to the setup function:
                            """
                        ),
                        CodeBlock(
                            """\
                            {
                                'jakewvincent/mkdnflow.nvim',
                                config = function()
                                    require('mkdnflow').setup({})
                                end
                            }"""
                        ),
                    ],
                ),
                Section(
                    title="Advanced configuration and sample recipes",
                    tag="config-advanced",
                    emoji="🔧",
                    content=[
                        Prose(
                            """
                            Most features are highly configurable. Study the default config first
                            and read the documentation for the configuration options below or in
                            the help files.
                            """
                        ),
                        Collapsible(
                            summary="🔧 Complete default config",
                            content=[CodeBlock(DEFAULT_CONFIG)],
                        ),
                    ],
                    children=[
                        Section(
                            title="Configuration options",
                            tag="config-options",
                            emoji="🎨",
                            children=[
                                Section(
                                    title="modules",
                                    tag="config-modules",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                modules = {
                                                    bib = true,
                                                    buffers = true,
                                                    conceal = true,
                                                    cursor = true,
                                                    folds = true,
                                                    foldtext = true,
                                                    links = true,
                                                    lists = true,
                                                    maps = true,
                                                    paths = true,
                                                    tables = true,
                                                    to_do = true,
                                                    yaml = false,
                                                    cmp = false,
                                                }
                                            })"""
                                        ),
                                        ConfigOptionTable(options=MODULES_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="create_dirs",
                                    tag="config-create-dirs",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                create_dirs = true,
                                            })"""
                                        ),
                                        ConfigOptionTable(options=CREATE_DIRS_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="perspective",
                                    tag="config-perspective",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                perspective = {
                                                    priority = 'first',
                                                    fallback = 'current',
                                                    root_tell = false,
                                                    nvim_wd_heel = false,
                                                    update = false,
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=PERSPECTIVE_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="filetypes",
                                    tag="config-filetypes",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                filetypes = {
                                                    md = true,
                                                    rmd = true,
                                                    markdown = true,
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=FILETYPES_OPTIONS),
                                        Admonition(
                                            "note",
                                            """
                                            This functionality references the file's extension. It does not rely on
                                            Neovim's filetype recognition. The extension must be provided in lower case
                                            because the plugin converts file names to lowercase. Any arbitrary extension
                                            can be supplied. Setting an extension to `false` is the same as not including
                                            it in the list.
                                            """,
                                        ),
                                    ],
                                ),
                                Section(
                                    title="wrap",
                                    tag="config-wrap",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                wrap = false,
                                            })"""
                                        ),
                                        ConfigOptionTable(options=WRAP_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="bib",
                                    tag="config-bib",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                bib = {
                                                    default_path = nil,
                                                    find_in_root = true,
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=BIB_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="silent",
                                    tag="config-silent",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                silent = false,
                                            })"""
                                        ),
                                        ConfigOptionTable(options=SILENT_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="cursor",
                                    tag="config-cursor",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                cursor = {
                                                    jump_patterns = nil,
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=CURSOR_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="links",
                                    tag="config-links",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                links = {
                                                    style = 'markdown',
                                                    name_is_source = false,
                                                    conceal = false,
                                                    context = 0,
                                                    implicit_extension = nil,
                                                    transform_implicit = false,
                                                    transform_explicit = function(text)
                                                        text = text:gsub(" ", "-")
                                                        text = text:lower()
                                                        text = os.date('%Y-%m-%d_') .. text
                                                        return(text)
                                                    end,
                                                    create_on_follow_failure = true,
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=LINKS_OPTIONS),
                                        Collapsible(
                                            summary="Sample links recipes",
                                            content=[
                                                CodeBlock(
                                                    """\
                                                    require('mkdnflow').setup({
                                                        links = {
                                                            -- If you want all link paths to be explicitly prefixed with the year
                                                            -- and for the path to be converted to uppercase:
                                                            transform_explicit = function(input)
                                                                return(string.upper(os.date('%Y-')..input))
                                                            end,
                                                            -- Link paths that match a date pattern can be opened in a `journals`
                                                            -- subdirectory of your notebook, and all others can be opened in a
                                                            -- `pages` subdirectory:
                                                            transform_implicit = function(input)
                                                                if input:match('%d%d%d%d%-%d%d%-%d%d') then
                                                                    return('journals/'..input)
                                                                else
                                                                    return('pages/'..input)
                                                                end
                                                            end
                                                        }
                                                    })"""
                                                ),
                                            ],
                                        ),
                                    ],
                                ),
                                Section(
                                    title="new_file_template",
                                    tag="config-new-file-template",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                new_file_template = {
                                                    use_template = false,
                                                    placeholders = {
                                                        before = { title = 'link_title', date = 'os_date' },
                                                        after = {},
                                                    },
                                                    template = '# {{ title }}',
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=NEW_FILE_TEMPLATE_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="to_do",
                                    tag="config-to-do",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                to_do = {
                                                    highlight = false,
                                                    status_propagation = { up = true, down = true },
                                                    sort = {
                                                        on_status_change = false,
                                                        recursive = false,
                                                        cursor_behavior = { track = true },
                                                    },
                                                    statuses = { ... },  -- See full default in docs
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=TO_DO_OPTIONS),
                                        Admonition(
                                            "warning",
                                            """
                                            The following to-do configuration options are deprecated. Please use the
                                            `to_do.statuses` table instead. Continued support for these options is
                                            temporarily provided by a compatibility layer that will be removed in the
                                            near future.

                                            * `to_do.symbols` - A list of markers representing to-do completion statuses
                                            * `to_do.not_started` - Which marker represents a not-yet-started to-do
                                            * `to_do.in_progress` - Which marker represents an in-progress to-do
                                            * `to_do.complete` - Which marker represents a complete to-do
                                            * `to_do.update_parents` - Whether parent to-dos' statuses should be updated
                                            """,
                                        ),
                                    ],
                                ),
                                Section(
                                    title="foldtext",
                                    tag="config-foldtext",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                foldtext = {
                                                    object_count = true,
                                                    object_count_icon_set = 'emoji',
                                                    object_count_opts = function()
                                                        return require('mkdnflow').foldtext.default_count_opts
                                                    end,
                                                    line_count = true,
                                                    line_percentage = true,
                                                    word_count = false,
                                                    title_transformer = function()
                                                        return require('mkdnflow').foldtext.default_title_transformer
                                                    end,
                                                    fill_chars = {
                                                        left_edge = '⢾⣿⣿',
                                                        right_edge = '⣿⣿⡷',
                                                        item_separator = ' · ',
                                                        section_separator = ' ⣹⣿⣏ ',
                                                        left_inside = ' ⣹',
                                                        right_inside = '⣏ ',
                                                        middle = '⣿',
                                                    },
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=FOLDTEXT_OPTIONS),
                                        Collapsible(
                                            summary="Sample foldtext recipes",
                                            content=[
                                                CodeBlock(
                                                    """\
                                                    -- SAMPLE FOLDTEXT CONFIGURATION RECIPE WITH COMMENTS
                                                    require('mkdnflow').setup({
                                                        foldtext = {
                                                            title_transformer = function()
                                                                local function my_title_transformer(text)
                                                                    local updated_title = text:gsub('%b{}', '')
                                                                    updated_title = updated_title:gsub('^%s*', '')
                                                                    updated_title = updated_title:gsub('%s*$', '')
                                                                    updated_title = updated_title:gsub('^######', '░░░░░▓')
                                                                    updated_title = updated_title:gsub('^#####', '░░░░▓▓')
                                                                    updated_title = updated_title:gsub('^####', '░░░▓▓▓')
                                                                    updated_title = updated_title:gsub('^###', '░░▓▓▓▓')
                                                                    updated_title = updated_title:gsub('^##', '░▓▓▓▓▓')
                                                                    updated_title = updated_title:gsub('^#', '▓▓▓▓▓▓')
                                                                    return updated_title
                                                                end
                                                                return my_title_transformer
                                                            end,
                                                            object_count_icon_set = 'nerdfont',
                                                            object_count_opts = function()
                                                                local opts = {
                                                                    link = false,
                                                                    blockquote = {
                                                                        icon = ' ',
                                                                        count_method = {
                                                                            pattern = { '^>.+$' },
                                                                            tally = 'blocks',
                                                                        }
                                                                    },
                                                                    fncblk = { icon = ' ' }
                                                                }
                                                                return opts
                                                            end,
                                                            line_count = false,
                                                            word_count = true,
                                                            fill_chars = {
                                                                left_edge = '╾─🖿 ─',
                                                                right_edge = '──╼',
                                                                item_separator = ' · ',
                                                                section_separator = ' // ',
                                                                left_inside = ' ┝',
                                                                right_inside = '┥ ',
                                                                middle = '─',
                                                            },
                                                        },
                                                    })"""
                                                ),
                                                Prose(
                                                    """
                                                    The above recipe will produce foldtext like the following
                                                    (for an h3-level section heading called `My section`):
                                                    """
                                                ),
                                                ResponsiveImage(
                                                    light_url="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/foldtext/foldtext_ex.png",
                                                    dark_url="https://raw.githubusercontent.com/jakewvincent/mkdnflow.nvim/media/assets/foldtext/foldtext_ex_dark.png",
                                                    alt="Enhanced foldtext example",
                                                    centered=True,
                                                ),
                                            ],
                                        ),
                                    ],
                                ),
                                Section(
                                    title="tables",
                                    tag="config-tables",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                tables = {
                                                    trim_whitespace = true,
                                                    format_on_move = true,
                                                    auto_extend_rows = false,
                                                    auto_extend_cols = false,
                                                    style = {
                                                        cell_padding = 1,
                                                        separator_padding = 1,
                                                        outer_pipes = true,
                                                        mimic_alignment = true,
                                                    },
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=TABLES_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="yaml",
                                    tag="config-yaml",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                yaml = {
                                                    bib = { override = false },
                                                },
                                            })"""
                                        ),
                                        ConfigOptionTable(options=YAML_OPTIONS),
                                    ],
                                ),
                                Section(
                                    title="mappings",
                                    tag="config-mappings",
                                    content=[
                                        CodeBlock(
                                            """\
                                            require('mkdnflow').setup({
                                                mappings = {
                                                    MkdnEnter = { { 'n', 'v' }, '<CR>' },
                                                    MkdnGoBack = { 'n', '<BS>' },
                                                    MkdnGoForward = { 'n', '<Del>' },
                                                    MkdnMoveSource = { 'n', '<F2>' },
                                                    MkdnNextLink = { 'n', '<Tab>' },
                                                    MkdnPrevLink = { 'n', '<S-Tab>' },
                                                    MkdnFollowLink = false,
                                                    MkdnDestroyLink = { 'n', '<M-CR>' },
                                                    MkdnTagSpan = { 'v', '<M-CR>' },
                                                    MkdnYankAnchorLink = { 'n', 'yaa' },
                                                    MkdnYankFileAnchorLink = { 'n', 'yfa' },
                                                    MkdnNextHeading = { 'n', ']]' },
                                                    MkdnPrevHeading = { 'n', '[[' },
                                                    MkdnIncreaseHeading = { 'n', '+' },
                                                    MkdnDecreaseHeading = { 'n', '-' },
                                                    MkdnToggleToDo = { { 'n', 'v' }, '<C-Space>' },
                                                    MkdnNewListItem = false,
                                                    MkdnNewListItemBelowInsert = { 'n', 'o' },
                                                    MkdnNewListItemAboveInsert = { 'n', 'O' },
                                                    MkdnExtendList = false,
                                                    MkdnUpdateNumbering = { 'n', '<leader>nn' },
                                                    MkdnTableNextCell = { 'i', '<Tab>' },
                                                    MkdnTablePrevCell = { 'i', '<S-Tab>' },
                                                    MkdnTableNextRow = false,
                                                    MkdnTablePrevRow = { 'i', '<M-CR>' },
                                                    MkdnTableNewRowBelow = { 'n', '<leader>ir' },
                                                    MkdnTableNewRowAbove = { 'n', '<leader>iR' },
                                                    MkdnTableNewColAfter = { 'n', '<leader>ic' },
                                                    MkdnTableNewColBefore = { 'n', '<leader>iC' },
                                                    MkdnFoldSection = { 'n', '<leader>f' },
                                                    MkdnUnfoldSection = { 'n', '<leader>F' },
                                                    MkdnTab = false,
                                                    MkdnSTab = false,
                                                    MkdnCreateLink = false,
                                                    MkdnCreateLinkFromClipboard = { { 'n', 'v' }, '<leader>p' },
                                                },
                                            })"""
                                        ),
                                        Prose(
                                            """
                                            See descriptions of commands and mappings below.

                                            **Note**: `<command>` should be the name of a command defined in
                                            `mkdnflow.nvim/plugin/mkdnflow.lua` (see `:h Mkdnflow-commands` for a list).
                                            """
                                        ),
                                        ConfigOptionTable(options=MAPPINGS_OPTIONS),
                                    ],
                                ),
                            ],
                        ),
                        Section(
                            title="Completion setup",
                            tag="completion-setup",
                            emoji="🔮",
                            content=[
                                Prose(
                                    """
                                    To enable completion via `cmp` using the provided source, add `mkdnflow` as a
                                    source in your `cmp` setup function. You may also want to modify the formatting
                                    to see which completions are coming from Mkdnflow:
                                    """
                                ),
                                CodeBlock(
                                    """\
                                    cmp.setup({
                                        -- Add 'mkdnflow' as a completion source
                                        sources = cmp.config.sources({
                                            { name = 'mkdnflow' },
                                        }),
                                        -- Completion source attribution
                                        formatting = {
                                            format = function(entry, vim_item)
                                                vim_item.menu = ({
                                                    -- Other attributions
                                                    mkdnflow = '[Mkdnflow]',
                                                })[entry.source_name]
                                                return vim_item
                                            end
                                        }
                                    })"""
                                ),
                                Admonition(
                                    "warning",
                                    """
                                    There may be some compatibility issues with the completion module and
                                    `links.transform_explicit`/`links.transform_implicit` functions.

                                    If you have some `transform_explicit` option for links to organizing in folders
                                    then the folder name will be inserted accordingly. Some transformations may not
                                    work as expected in completions.

                                    To prevent this, make sure you write sensible transformation functions,
                                    preferably using it for folder organization.
                                    """,
                                ),
                            ],
                        ),
                    ],
                ),
            ],
        ),
        # =====================================================================
        # COMMANDS & MAPPINGS
        # =====================================================================
        Section(
            title="Commands & mappings",
            tag="commands",
            emoji="🛠️",
            content=[
                Prose(
                    """
                    Below are descriptions of the user commands defined by Mkdnflow. For the
                    default mappings to these commands, see the `mappings = ...` section of
                    Configuration options.
                    """
                ),
                CommandTable(commands=COMMANDS),
                Admonition(
                    "tip",
                    """
                    If you are attempting to (re)map `<CR>` in insert mode but can't get it to
                    work, try inspecting your current insert mode mappings and seeing if anything
                    is overriding your mapping. Possible candidates are completion plugins and
                    auto-pair plugins.

                    If using nvim-cmp, consider using the mapping with a fallback.
                    If using an autopair plugin that automatically maps `<CR>` (e.g. nvim-autopairs),
                    see if it provides a way to disable its `<CR>` mapping.
                    """,
                ),
            ],
        ),
        # =====================================================================
        # API
        # =====================================================================
        Section(
            title="API",
            tag="api",
            emoji="📚",
            content=[
                Prose(
                    """
                    Mkdnflow provides a range of Lua functions that can be called directly to
                    manipulate markdown files, navigate through buffers, manage links, and more.
                    Below are the primary functions available:
                    """
                ),
                BulletList(
                    ordered=True,
                    items=[
                        ListItem("Initialization (see `initialization`)"),
                        ListItem("Link management (see `linkmanagement`)"),
                        ListItem("Link & path handling (see `linkpathhandling`)"),
                        ListItem("Buffer navigation (see `buffernavigation`)"),
                        ListItem("Cursor movement (see `cursormovement`)"),
                        ListItem("Cursor-aware manipulations (see `cursorawaremanipulations`)"),
                        ListItem("List management (see `listmanagement`)"),
                        ListItem("To-do list management (see `todolistmanagement`)"),
                        ListItem("Table management (see `tablemanagement`)"),
                        ListItem("Folds (see `folds`)"),
                        ListItem("Yaml blocks (see `yamlblocks`)"),
                        ListItem("Bibliography (see `bibliography`)"),
                    ],
                ),
            ],
            children=[
                # API: Initialization
                Section(
                    title="Initialization",
                    tag="initialization",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').setup(config)",
                            description="""
                                Initializes the plugin with the provided configuration. See Advanced
                                configuration and sample recipes. If called with an empty table, the
                                default configuration is used.
                            """,
                            params=[
                                ApiParam(
                                    name="config",
                                    type="table",
                                    description="Configuration table containing various settings such as filetypes, modules, mappings, and more.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').forceStart(opts)",
                            description="""
                                Similar to setup, but forces the initialization of the plugin regardless
                                of the current buffer's filetype.
                            """,
                            params=[
                                ApiParam(
                                    name="opts",
                                    type="table",
                                    description="Table of options.",
                                    children=[
                                        ApiParam(
                                            name="opts[1]",
                                            type="boolean",
                                            description="Whether to attempt initialization silently (`true`) or not (`false`).",
                                        ),
                                    ],
                                ),
                            ],
                        ),
                    ],
                ),
                # API: Link management
                Section(
                    title="Link management",
                    tag="linkmanagement",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').links.createLink(args)",
                            description="Creates a markdown link from the word under the cursor or visual selection.",
                            params=[
                                ApiParam(
                                    name="args",
                                    type="table",
                                    description="Arguments to customize link creation.",
                                    children=[
                                        ApiParam(
                                            name="from_clipboard",
                                            type="boolean",
                                            description="If true, use the system clipboard content as the link source.",
                                        ),
                                    ],
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.followLink(args)",
                            description="Follows the link under the cursor, opening the corresponding file, URL, or directory. Image links are opened in the system's default image viewer.",
                            params=[
                                ApiParam(
                                    name="args",
                                    type="table",
                                    description="Arguments for following the link.",
                                    children=[
                                        ApiParam(
                                            name="path",
                                            type="string|nil",
                                            description="The path/source to follow. If `nil`, a path from a link under the cursor will be used.",
                                        ),
                                        ApiParam(
                                            name="anchor",
                                            type="string|nil",
                                            description="An anchor, either one in the current buffer (in which case `path` will be `nil`), or one in the file referred to in `path`.",
                                        ),
                                        ApiParam(
                                            name="range",
                                            type="boolean|nil",
                                            description="Whether a link should be created from a visual selection range. This is only relevant if `create_on_follow_failure` is `true`, there is no link under the cursor, and there is currently a visual selection that needs to be made into a link.",
                                        ),
                                    ],
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.destroyLink()",
                            description="Destroys the link under the cursor, replacing it with plain text.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.tagSpan()",
                            description="Tags a visual selection as a span, useful for adding attributes to specific text segments.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.getLinkUnderCursor(col)",
                            description="Returns the link under the cursor at the specified column.",
                            params=[
                                ApiParam(
                                    name="col",
                                    type="number|nil",
                                    description="The column position to check for a link. The current cursor position is used if this is not specified.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.getLinkPart(link_table, part)",
                            description="Retrieves a specific part of a link, such as the source or the text.",
                            params=[
                                ApiParam(
                                    name="link_table",
                                    type="table",
                                    description="The table containing link details, as provided by `require('mkdnflow').links.getLinkUnderCursor()`.",
                                ),
                                ApiParam(
                                    name="part",
                                    type="string|nil",
                                    description="The part of the link to retrieve (one of `'source'`, `'name'`, or `'anchor'`). Default: `'source'`.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.getBracketedSpanPart(part)",
                            description="Retrieves a specific part of a bracketed span.",
                            params=[
                                ApiParam(
                                    name="part",
                                    type="string|nil",
                                    description="The part of the span to retrieve (one of `'text'` or `'attr'`). Default: `'attr'`.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.hasUrl(string, to_return, col)",
                            description="Checks if a given string contains a URL and optionally returns the URL.",
                            params=[
                                ApiParam(name="string", type="string", description="The string to check for a URL."),
                                ApiParam(name="to_return", type="string", description='The part to return (e.g., "url").'),
                                ApiParam(name="col", type="number", description="The column position to check."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.transformPath(text)",
                            description="Transforms the given text according to the default or user-supplied explicit transformation function.",
                            params=[
                                ApiParam(name="text", type="string", description="The text to transform."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').links.formatLink(text, source, part)",
                            description="Creates a formatted link with whatever is provided.",
                            params=[
                                ApiParam(name="text", type="string", description="The link text."),
                                ApiParam(name="source", type="string", description="The link source."),
                                ApiParam(
                                    name="part",
                                    type="integer|nil",
                                    description="The specific part of the link to return.",
                                    children=[
                                        ApiParam(name="nil", type="", description="Return the entire link."),
                                        ApiParam(name="1", type="", description="Return the text part of the link."),
                                        ApiParam(name="2", type="", description="Return the source part of the link."),
                                    ],
                                ),
                            ],
                        ),
                    ],
                ),
                # API: Link and path handling
                Section(
                    title="Link and path handling",
                    tag="linkpathhandling",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').paths.moveSource()",
                            description="Moves the source file of a link to a new location, updating the link accordingly.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').paths.handlePath(path, anchor)",
                            description="Handles all 'following' behavior for a given path, potentially opening it or performing other actions based on the type.",
                            params=[
                                ApiParam(name="path", type="string", description="The path to handle."),
                                ApiParam(name="anchor", type="string|nil", description="Optional anchor within the path."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').paths.formatTemplate(timing, template)",
                            description="""
                                Formats the new file template based on the specified timing (before or
                                after buffer creation). If this is called once with 'before' timing,
                                the output can be captured and passed back in with 'after' timing to
                                perform different substitutions before and after a new buffer is opened.
                            """,
                            params=[
                                ApiParam(
                                    name="timing",
                                    type="string",
                                    description='"before" or "after" specifying when to perform the formatting.',
                                    children=[
                                        ApiParam(name="'before'", type="", description="Perform the template formatting before the new buffer is opened."),
                                        ApiParam(name="'after'", type="", description="Perform the template formatting after the new buffer is opened."),
                                    ],
                                ),
                                ApiParam(
                                    name="template",
                                    type="string|nil",
                                    description="The template to format. If not provided, the default new file template is used.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').paths.updateDirs()",
                            description="Updates the working directory after switching notebooks or notebook folders (if `nvim_wd_heel` is true).",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').paths.pathType(path, anchor)",
                            description="Determines the type of the given path (file, directory, URL, etc.).",
                            params=[
                                ApiParam(name="path", type="string", description="The path to check."),
                                ApiParam(name="anchor", type="string|nil", description="Optional anchor within the path."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').paths.transformPath(path)",
                            description="Transforms the given path based on the plugin's configuration and transformations.",
                            params=[
                                ApiParam(name="path", type="string", description="The path to transform."),
                            ],
                        ),
                    ],
                ),
                # API: Buffer navigation
                Section(
                    title="Buffer navigation",
                    tag="buffernavigation",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').buffers.goBack()",
                            description="Navigates to the previously opened buffer.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').buffers.goForward()",
                            description="Navigates to the next buffer in the history.",
                        ),
                    ],
                ),
                # API: Cursor movement
                Section(
                    title="Cursor movement",
                    tag="cursormovement",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').cursor.goTo(pattern, reverse)",
                            description="Moves the cursor to the next or previous occurrence of the specified pattern.",
                            params=[
                                ApiParam(name="pattern", type="string|table", description="The Lua regex pattern(s) to search for."),
                                ApiParam(name="reverse", type="boolean", description="If true, search backward."),
                            ],
                            example='require(\'mkdnflow\').cursor.goTo("%[.*%](.*)", false) -- Go to next markdown link',
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').cursor.toNextLink()",
                            description="Moves the cursor to the next link in the file.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').cursor.toPrevLink()",
                            description="Moves the cursor to the previous link in the file.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').cursor.toHeading(anchor_text, reverse)",
                            description="Moves the cursor to the specified heading.",
                            params=[
                                ApiParam(
                                    name="anchor_text",
                                    type="string|nil",
                                    description="The text of the heading to move to, transformed in the way that is expected for an anchor link to a heading. If `nil`, the function will go to the next closest heading.",
                                ),
                                ApiParam(name="reverse", type="boolean", description="If true, search backward."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').cursor.toId(id, starting_row)",
                            description="Moves the cursor to the specified ID in the file.",
                            params=[
                                ApiParam(name="id", type="string", description="The Pandoc-style ID attribute (in a tagged span) to move to."),
                                ApiParam(
                                    name="starting_row",
                                    type="number|nil",
                                    description="The row to start the search from. If not provided, the cursor row will be used.",
                                ),
                            ],
                        ),
                    ],
                ),
                # API: Cursor-aware manipulations
                Section(
                    title="Cursor-aware manipulations",
                    tag="cursorawaremanipulations",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').cursor.changeHeadingLevel(change)",
                            description='Increases or decreases the importance of the heading under the cursor by adjusting the number of hash symbols.',
                            params=[
                                ApiParam(
                                    name="change",
                                    type="string",
                                    description='"increase" to decrease hash symbols (increasing importance), "decrease" to add hash symbols, decreasing importance.',
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').cursor.yankAsAnchorLink(full_path)",
                            description="Yanks the current line as an anchor link, optionally including the full file path depending on the value of the argument.",
                            params=[
                                ApiParam(name="full_path", type="boolean", description="If true, includes the full file path."),
                            ],
                        ),
                    ],
                ),
                # API: List management
                Section(
                    title="List management",
                    tag="listmanagement",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').lists.newListItem({ carry, above, cursor_moves, mode_after, alt })",
                            description="Inserts a new list item with various customization options such as whether to carry content from the current line, position the new item above or below, and the editor mode after insertion.",
                            params=[
                                ApiParam(name="carry", type="boolean", description="Whether to carry content following the cursor on the current line into the new line/list item."),
                                ApiParam(name="above", type="boolean", description="Whether to insert the new item above the current line."),
                                ApiParam(name="cursor_moves", type="boolean", description="Whether the cursor should move to the new line."),
                                ApiParam(name="mode_after", type="string", description='The mode to enter after insertion ("i" for insert, "n" for normal).'),
                                ApiParam(name="alt", type="string", description="Which key(s) to feed if this is called while the cursor is not on a line with a list item. Must be a valid string for the first argument of `vim.api.nvim_feedkeys`."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').lists.hasListType(line)",
                            description="Checks if the given line is part of a list.",
                            params=[
                                ApiParam(name="line", type="string", description="The (content of the) line to check. If not provided, the current cursor line will be used."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').lists.toggleToDo(opts)",
                            description="Toggles (rotates) the status of a to-do list item based on the provided options.",
                            params=[
                                ApiParam(name="opts", type="table", description="Options for toggling."),
                            ],
                        ),
                        Admonition(
                            "warning",
                            """
                            `require('mkdnflow').lists.toggleToDo(opts)` is deprecated. For convenience, it is
                            now a wrapper function that calls its replacement, `require('mkdnflow').to_do.toggle_to_do(opts)`.
                            See `require('mkdnflow').to_do.toggle_to_do()` for details.
                            """,
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').lists.updateNumbering(opts, offset)",
                            description="Updates the numbering of the list items in the current list.",
                            params=[
                                ApiParam(
                                    name="opts",
                                    type="table",
                                    description="Options for updating numbering.",
                                    children=[
                                        ApiParam(name="opts[1]", type="integer", description="The number to start the current ordered list with."),
                                    ],
                                ),
                                ApiParam(name="offset", type="number", description="The offset to start numbering from. Defaults to `0` if not provided."),
                            ],
                        ),
                    ],
                ),
                # API: To-do list management
                Section(
                    title="To-do list management",
                    tag="todolistmanagement",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').to_do.toggle_to_do()",
                            description="Toggle (rotate) to-do statuses for a to-do item under the cursor.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').to_do.get_to_do_item(line_nr)",
                            description="Retrieves a to-do item from the specified line number.",
                            params=[
                                ApiParam(name="line_nr", type="number", description="The line number to retrieve the to-do item from. If not provided, defaults to the cursor line number."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').to_do.get_to_do_list(line_nr)",
                            description="Retrieves the entire to-do list of which the specified line number is an item/member.",
                            params=[
                                ApiParam(name="line_nr", type="number", description="The line number to retrieve the to-do list from. If not provided, defaults to the cursor line number."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').to_do.hl.init()",
                            description="Initializes highlighting for to-do items. If highlighting is enabled in your configuration, you should never need to use this.",
                        ),
                    ],
                ),
                # API: Table management
                Section(
                    title="Table management",
                    tag="tablemanagement",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').tables.formatTable()",
                            description="Formats the current table, ensuring proper alignment and spacing.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').tables.addRow(offset)",
                            description="Adds a new row to the table at the specified offset.",
                            params=[
                                ApiParam(
                                    name="offset",
                                    type="number",
                                    description="The position (relative to the current cursor row) in which to insert the new row. Defaults to `0`, in which case a new row is added beneath the current cursor row. An offset of `-1` will result in a row being inserted _above_ the current cursor row; an offset of `1` will result in a row being inserted after the row following the current cursor row; etc.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').tables.addCol(offset)",
                            description="Adds a new column to the table at the specified offset.",
                            params=[
                                ApiParam(
                                    name="offset",
                                    type="number",
                                    description="The position (relative to the table column the cursor is currently in) to insert the new column. Defaults to `0`, in which case a new column is added after the current cursor table column. An offset of `-1` will result in a column being inserted _before_ the current cursor table column; an offset of `1` will result in a column being inserted after the column following the current cursor table column; etc.",
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').tables.newTable(opts)",
                            description="Creates a new table with the specified options.",
                            params=[
                                ApiParam(
                                    name="opts",
                                    type="table",
                                    description="Options for the new table (number of columns and rows).",
                                    children=[
                                        ApiParam(name="opts[1]", type="integer", description="The number of columns the table should have"),
                                        ApiParam(name="opts[2]", type="integer", description="The number of rows the table should have (excluding the header row)"),
                                        ApiParam(
                                            name="opts[3]",
                                            type="string",
                                            description="Whether to include a header for the table or not (`'noh'` or `'noheader'`: Don't include a header row; `nil`: Include a header)",
                                        ),
                                    ],
                                ),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').tables.isPartOfTable(text, linenr)",
                            description="Guesses as to whether the specified text is part of a table.",
                            params=[
                                ApiParam(name="text", type="string", description="The content to check for table membership."),
                                ApiParam(name="linenr", type="number", description="The line number corresponding to the text passed in."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').tables.moveToCell(row_offset, cell_offset)",
                            description="Moves the cursor to the specified cell in the table.",
                            params=[
                                ApiParam(name="row_offset", type="number", description="The difference between the current row and the target row. `0`, for instance, will target the current row."),
                                ApiParam(name="cell_offset", type="number", description="The difference between the current table column and the target table column. `0`, for instance, will target the current column."),
                            ],
                        ),
                    ],
                ),
                # API: Folds
                Section(
                    title="Folds",
                    tag="folds",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').folds.getHeadingLevel(line)",
                            description="Gets the heading level of the specified line.",
                            params=[
                                ApiParam(name="line", type="string", description="The line content to get the heading level for. Required."),
                            ],
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').folds.foldSection()",
                            description="Folds the current section based on markdown headings.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').folds.unfoldSection()",
                            description="Unfolds the current section.",
                        ),
                    ],
                ),
                # API: Yaml blocks
                Section(
                    title="Yaml blocks",
                    tag="yamlblocks",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').yaml.hasYaml()",
                            description="Checks if the current buffer contains a YAML header block.",
                        ),
                        ApiFunction(
                            signature="require('mkdnflow').yaml.ingestYamlBlock(start, finish)",
                            description="Parses and ingests a YAML block from the specified range.",
                            params=[
                                ApiParam(name="start", type="number", description="The starting line number."),
                                ApiParam(name="finish", type="number", description="The ending line number."),
                            ],
                        ),
                    ],
                ),
                # API: Bibliography
                Section(
                    title="Bibliography",
                    tag="bibliography",
                    content=[
                        ApiFunction(
                            signature="require('mkdnflow').bib.handleCitation(citation)",
                            description="Handles a citation, potentially linking to a bibliography entry or external source.",
                            params=[
                                ApiParam(name="citation", type="string", description="The citation key to handle. Required."),
                            ],
                        ),
                    ],
                ),
            ],
        ),
        # =====================================================================
        # CONTRIBUTING
        # =====================================================================
        Section(
            title="Contributing",
            tag="contributing",
            emoji="🤝",
            content=[
                Prose(
                    """
                    See [CONTRIBUTING.md](https://github.com/jakewvincent/mkdnflow.nvim/blob/main/CONTRIBUTING.md)
                    """
                ),
            ],
        ),
        # =====================================================================
        # VERSION INFORMATION
        # =====================================================================
        Section(
            title="Version information",
            tag="versioninformation",
            emoji="🔢",
            content=[
                Prose(
                    """
                    Mkdnflow uses [Semantic Versioning](https://semver.org/). Version numbers
                    follow the format MAJOR.MINOR.PATCH:
                    """
                ),
                BulletList(
                    items=[
                        ListItem("**MAJOR**: Incompatible API or configuration changes"),
                        ListItem("**MINOR**: New functionality in a backward-compatible manner"),
                        ListItem("**PATCH**: Backward-compatible bug fixes"),
                    ]
                ),
                Prose(
                    """
                    For a detailed history of changes, see
                    [CHANGELOG.md](https://github.com/jakewvincent/mkdnflow.nvim/blob/main/CHANGELOG.md).
                    """
                ),
            ],
        ),
        # =====================================================================
        # RELATED PROJECTS
        # =====================================================================
        Section(
            title="Related projects",
            tag="related",
            emoji="🔗",
            children=[
                Section(
                    title="Competition",
                    tag="related-competition",
                    content=[
                        BulletList(
                            items=[
                                ListItem("[obsidian.nvim](https://github.com/epwalsh/obsidian.nvim)"),
                                ListItem("[wiki.vim](https://github.com/lervag/wiki.vim/)"),
                                ListItem("[Neorg](https://github.com/nvim-neorg/neorg)"),
                                ListItem("[markdown.nvim](https://github.com/tadmccorkle/markdown.nvim)"),
                                ListItem("[Vimwiki](https://github.com/vimwiki/vimwiki)"),
                                ListItem("[follow-md-links.nvim](https://github.com/jghauser/follow-md-links.nvim)"),
                            ]
                        ),
                    ],
                ),
                Section(
                    title="Complementary plugins",
                    tag="related-complementary",
                    content=[
                        BulletList(
                            items=[
                                ListItem("[Obsidian.md](https://obsidian.md)"),
                                ListItem("[clipboard-image.nvim](https://github.com/ekickx/clipboard-image.nvim)"),
                                ListItem("[mdeval.nvim](https://github.com/jubnzv/mdeval.nvim)"),
                                ListItem(
                                    "In-editor rendering",
                                    children=[
                                        ListItem("[render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)"),
                                        ListItem("[markview.nvim](https://github.com/OXY2DEV/markview.nvim)"),
                                    ],
                                ),
                                ListItem(
                                    "Preview plugins",
                                    children=[
                                        ListItem("[Markdown Preview for (Neo)vim](https://github.com/iamcco/markdown-preview.nvim)"),
                                        ListItem("[nvim-markdown-preview](https://github.com/davidgranstrom/nvim-markdown-preview)"),
                                        ListItem("[glow.nvim](https://github.com/npxbr/glow.nvim)"),
                                        ListItem("[auto-pandoc.nvim](https://github.com/jghauser/auto-pandoc.nvim)"),
                                    ],
                                ),
                            ]
                        ),
                    ],
                ),
            ],
        ),
    ]


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
