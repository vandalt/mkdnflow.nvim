# Author: Jake W. Vincent
import csv
import re
import os
import sys


def log_info(message):
    """Print an informational message."""
    print(f"INFO: {message}")


def log_warning(message):
    """Print a warning message."""
    print(f"WARNING: {message}", file=sys.stderr)


def log_error(message):
    """Print an error message."""
    print(f"ERROR: {message}", file=sys.stderr)


def read_csv(path):
    try:
        with open(path, 'r', encoding='utf-8') as f:
            try:
                reader = csv.DictReader(f)
                # Check if the CSV has any columns
                if not reader.fieldnames:
                    log_error(f"CSV file '{path}' has no columns")
                    sys.exit(1)
                
                data = [row for row in reader]
                
                # Check if the CSV has any rows
                if not data:
                    log_warning(f"CSV file '{path}' has no data rows, will generate an empty table")
                    # Create an empty row with empty values for each field
                    empty_row = {field: "" for field in reader.fieldnames}
                    return [empty_row]
                
                return data
            except csv.Error as e:
                log_error(f"CSV parsing error in '{path}': {e}")
                sys.exit(1)
    except FileNotFoundError:
        log_error(f"CSV file '{path}' not found")
        sys.exit(1)
    except IOError as e:
        log_error(f"I/O error reading '{path}': {e}")
        sys.exit(1)
    except Exception as e:
        log_error(f"Unexpected error reading '{path}': {e}")
        sys.exit(1)


def replace_smart_quotes(text):
    """Replace smart quotes with regular quotes."""
    return text.replace('“', '"').replace('”', '"').replace("’", "'").replace("‘", "'")


def format_as_md(lst):
    try:
        # Get column names
        colnames = list(lst[0])

        # Organize data by column (so it's easy to get the max char width for each column)
        cols = {col: [row[col].replace("\n", "<br>").strip() if col in row else "" for row in lst] for col in colnames}
        max_widths = [max([len(cell) for cell in cols[col]] + [len(col)]) for col in cols]
        table = ""  # Initialize the string for the table

        # Add header row first
        for i, name in enumerate(colnames):
            cell = f"| {name} {' ' * (max_widths[i] - len(name))}"
            table += cell
        table += "|\n"

        # Add separator row
        for i in range(len(colnames)):
            table += f"| {'-' * max_widths[i]} "
        table += "|\n"

        # Add cells
        for i, row in enumerate(lst):
            for j, name in enumerate(colnames):
                cell_content = cols[name][i]
                cell = f"| {cell_content} {' ' * (max_widths[j] - len(cell_content))}"
                table += cell
            table += "|\n"

        # Strip smart quotes from CSV editor
        table = replace_smart_quotes(table)

        # Return the table w/o any adjacent whitespace
        return table.strip()
    except Exception as e:
        log_error(f"Error formatting markdown table: {e}")
        sys.exit(1)


def replace_placeholders(template, files):
    # Track which placeholders were replaced and which weren't
    replaced = []
    not_replaced = []
    
    # Iterate over matches of the placeholder pattern
    for match in re.findall(r"{{\s*(.*?)\s*}}", template):
        # Skip obvious template placeholders in code examples
        if match in ["title"]:
            continue

        csv_filename = f"{match}.csv"
        # Replace the placeholder if there's a matching csv file in ../data
        if csv_filename in files:
            try:
                log_info(f"Processing placeholder '{{{{ {match} }}}}' with data from {csv_filename}")
                csv_data = read_csv(os.path.join("data", csv_filename))
                md_table = format_as_md(csv_data)

                # Count occurrences to warn about multiple instances
                count = template.count(f"{{{{ {match} }}}}")
                if count > 1:
                    log_warning(f"Found {count} occurrences of placeholder '{{{{ {match} }}}}', only replacing the first one")

                # Perform one replacement
                new_template = re.sub(rf"{{{{\s*{match}\s*}}}}", md_table, template, 1)
                
                # Check if replacement occurred
                if new_template != template:
                    template = new_template
                    replaced.append(match)
                else:
                    log_warning(f"Failed to replace '{{{{ {match} }}}}' despite having matching CSV")
                    not_replaced.append(match)
            except Exception as e:
                log_error(f"Error replacing placeholder '{{{{ {match} }}}}': {e}")
                not_replaced.append(match)
        else:
            # Only warn about non-replaced placeholders that aren't likely in code examples
            if not any(code_example in match for code_example in ["title", "date"]):
                log_warning(f"No CSV file found for placeholder '{{{{ {match} }}}}'")
                not_replaced.append(match)

    # Report on replacements
    if replaced:
        log_info(f"Successfully replaced {len(replaced)} placeholders: {', '.join(replaced)}")
    if not_replaced:
        log_warning(f"Failed to replace {len(not_replaced)} placeholders: {', '.join(not_replaced)}")

    # The template with all possible substitutions made
    return template


def main():
    """Main function that orchestrates the README generation."""
    try:
        # Check if data directory exists
        if not os.path.isdir("data"):
            log_error("Data directory 'data/' not found")
            sys.exit(1)
            
        # Check if template exists
        if not os.path.isfile("README.template.md"):
            log_error("Template file 'README.template.md' not found")
            sys.exit(1)
        
        log_info("Starting README generation")
        
        # Read in the README template
        try:
            with open("README.template.md", "r", encoding="utf-8") as f:
                readme_template = f.read()
                log_info(f"Read template file (size: {len(readme_template)} bytes)")
        except FileNotFoundError:
            log_error("README.template.md not found")
            sys.exit(1)
        except IOError as e:
            log_error(f"I/O error reading README.template.md: {e}")
            sys.exit(1)

        # List the files in the data directory
        try:
            files = os.listdir("data/")
            csv_files = [f for f in files if f.endswith('.csv')]
            log_info(f"Found {len(csv_files)} CSV files in data/ directory")
        except FileNotFoundError:
            log_error("Data directory not found")
            sys.exit(1)
        except Exception as e:
            log_error(f"Error accessing data directory: {e}")
            sys.exit(1)

        # Format the README template
        formatted_readme = replace_placeholders(readme_template, files)

        # Write out the formatted README
        try:
            with open("README.md", "w", encoding="utf-8") as f:
                f.write(formatted_readme)
            log_info(f"Successfully wrote updated README.md (size: {len(formatted_readme)} bytes)")
        except IOError as e:
            log_error(f"I/O error writing README.md: {e}")
            sys.exit(1)
        
        log_info("README generation completed successfully")
        
    except Exception as e:
        log_error(f"Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
