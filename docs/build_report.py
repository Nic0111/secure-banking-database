from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_ALIGN_VERTICAL, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK, WD_LINE_SPACING, WD_TAB_ALIGNMENT, WD_TAB_LEADER
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


OUTPUT = Path(__file__).with_name("SmartBank_Database_Security_Report.docx")

NAVY = "203748"
BLUE = "2E74B5"
DARK_BLUE = "1F4D78"
MUTED = "667085"
INK = "222222"
LIGHT = "F2F4F7"
CALLOUT = "F4F6F9"
GOLD = "7A5A00"
RED = "9B1C1C"
WHITE = "FFFFFF"
TABLE_WIDTH = 9360
TABLE_INDENT = 120


def rgb(hex_value):
    return RGBColor.from_string(hex_value)


def set_run_font(run, name="Calibri", size=None, color=INK, bold=None, italic=None):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:ascii"), name)
    run._element.get_or_add_rPr().rFonts.set(qn("w:hAnsi"), name)
    if size is not None:
        run.font.size = Pt(size)
    if color:
        run.font.color.rgb = rgb(color)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.italic = italic


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    marker = OxmlElement("w:tblHeader")
    marker.set(qn("w:val"), "true")
    tr_pr.append(marker)


def prevent_row_split(row):
    tr_pr = row._tr.get_or_add_trPr()
    tr_pr.append(OxmlElement("w:cantSplit"))


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_table_geometry(table, widths):
    if sum(widths) != TABLE_WIDTH:
        raise ValueError(f"Table widths must total {TABLE_WIDTH}, got {sum(widths)}")
    table.autofit = False
    table.alignment = WD_TABLE_ALIGNMENT.LEFT
    tbl = table._tbl
    tbl_pr = tbl.tblPr

    tbl_w = tbl_pr.find(qn("w:tblW"))
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:w"), str(TABLE_WIDTH))
    tbl_w.set(qn("w:type"), "dxa")

    tbl_ind = tbl_pr.find(qn("w:tblInd"))
    if tbl_ind is None:
        tbl_ind = OxmlElement("w:tblInd")
        tbl_pr.append(tbl_ind)
    tbl_ind.set(qn("w:w"), str(TABLE_INDENT))
    tbl_ind.set(qn("w:type"), "dxa")

    layout = tbl_pr.find(qn("w:tblLayout"))
    if layout is None:
        layout = OxmlElement("w:tblLayout")
        tbl_pr.append(layout)
    layout.set(qn("w:type"), "fixed")

    cell_mar = tbl_pr.find(qn("w:tblCellMar"))
    if cell_mar is None:
        cell_mar = OxmlElement("w:tblCellMar")
        tbl_pr.append(cell_mar)
    for side, value in (("top", 80), ("bottom", 80), ("start", 120), ("end", 120)):
        node = cell_mar.find(qn(f"w:{side}"))
        if node is None:
            node = OxmlElement(f"w:{side}")
            cell_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")

    borders = tbl_pr.find(qn("w:tblBorders"))
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        node = borders.find(qn(f"w:{edge}"))
        if node is None:
            node = OxmlElement(f"w:{edge}")
            borders.append(node)
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), "4")
        node.set(qn("w:color"), "D0D5DD")

    grid = tbl.tblGrid
    for child in list(grid):
        grid.remove(child)
    for width in widths:
        col = OxmlElement("w:gridCol")
        col.set(qn("w:w"), str(width))
        grid.append(col)

    for row in table.rows:
        prevent_row_split(row)
        for index, cell in enumerate(row.cells):
            tc_pr = cell._tc.get_or_add_tcPr()
            tc_w = tc_pr.find(qn("w:tcW"))
            if tc_w is None:
                tc_w = OxmlElement("w:tcW")
                tc_pr.append(tc_w)
            tc_w.set(qn("w:w"), str(widths[index]))
            tc_w.set(qn("w:type"), "dxa")
            cell.vertical_alignment = WD_ALIGN_VERTICAL.CENTER


def style_table_text(cell, header=False, font_size=8.5):
    for paragraph in cell.paragraphs:
        paragraph.paragraph_format.space_before = Pt(0)
        paragraph.paragraph_format.space_after = Pt(2)
        paragraph.paragraph_format.line_spacing = 1.0
        for run in paragraph.runs:
            set_run_font(run, size=font_size, color=NAVY if header else INK, bold=header)


def add_table(doc, caption, headers, rows, widths, font_size=8.5, source=None):
    p = doc.add_paragraph(style="Table Caption")
    p.add_run(caption)
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    for index, value in enumerate(headers):
        cell = table.rows[0].cells[index]
        cell.text = str(value)
        set_cell_shading(cell, LIGHT)
        style_table_text(cell, header=True, font_size=font_size)
    set_repeat_table_header(table.rows[0])
    for row_values in rows:
        row = table.add_row()
        for index, value in enumerate(row_values):
            row.cells[index].text = "" if value is None else str(value)
            style_table_text(row.cells[index], font_size=font_size)
    set_table_geometry(table, widths)
    if source:
        source_p = doc.add_paragraph(style="Table Citation")
        source_p.add_run(source)
    return table


def add_field(paragraph, instruction, placeholder=""):
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = instruction
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    text = OxmlElement("w:t")
    text.text = placeholder
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.extend([begin, instr, separate, text, end])


def add_hyperlink(paragraph, text, url):
    part = paragraph.part
    relationship_id = part.relate_to(
        url,
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
        is_external=True,
    )
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), relationship_id)
    run = OxmlElement("w:r")
    run_properties = OxmlElement("w:rPr")
    color = OxmlElement("w:color")
    color.set(qn("w:val"), BLUE)
    underline = OxmlElement("w:u")
    underline.set(qn("w:val"), "single")
    run_properties.extend([color, underline])
    run.append(run_properties)
    label = OxmlElement("w:t")
    label.text = text
    run.append(label)
    hyperlink.append(run)
    paragraph._p.append(hyperlink)


def set_page_number_start(section, value):
    sect_pr = section._sectPr
    pg_num = sect_pr.find(qn("w:pgNumType"))
    if pg_num is None:
        pg_num = OxmlElement("w:pgNumType")
        sect_pr.append(pg_num)
    pg_num.set(qn("w:start"), str(value))


def setup_numbering(doc):
    numbering = doc.part.numbering_part.element
    try:
        abstract_ids = [int(node.get(qn("w:abstractNumId"))) for node in numbering.findall(qn("w:abstractNum"))]
        num_ids = [int(node.get(qn("w:numId"))) for node in numbering.findall(qn("w:num"))]
    except (AttributeError, TypeError, ValueError) as exc:
        raise ValueError(f"Unable to read numbering definitions from the report template: {exc}") from exc
    next_abstract = max(abstract_ids or [0]) + 1
    next_num = max(num_ids or [0]) + 1

    def make_numbering(abstract_id, num_id, fmt, text, font=None):
        abstract = OxmlElement("w:abstractNum")
        abstract.set(qn("w:abstractNumId"), str(abstract_id))
        multi = OxmlElement("w:multiLevelType")
        multi.set(qn("w:val"), "singleLevel")
        abstract.append(multi)
        level = OxmlElement("w:lvl")
        level.set(qn("w:ilvl"), "0")
        start = OxmlElement("w:start")
        start.set(qn("w:val"), "1")
        num_fmt = OxmlElement("w:numFmt")
        num_fmt.set(qn("w:val"), fmt)
        level_text = OxmlElement("w:lvlText")
        level_text.set(qn("w:val"), text)
        justification = OxmlElement("w:lvlJc")
        justification.set(qn("w:val"), "left")
        p_pr = OxmlElement("w:pPr")
        tabs = OxmlElement("w:tabs")
        tab = OxmlElement("w:tab")
        tab.set(qn("w:val"), "num")
        tab.set(qn("w:pos"), "720")
        tabs.append(tab)
        indent = OxmlElement("w:ind")
        indent.set(qn("w:left"), "720")
        indent.set(qn("w:hanging"), "360")
        spacing = OxmlElement("w:spacing")
        spacing.set(qn("w:after"), "160")
        spacing.set(qn("w:line"), "280")
        spacing.set(qn("w:lineRule"), "auto")
        p_pr.extend([tabs, indent, spacing])
        level.extend([start, num_fmt, level_text, justification, p_pr])
        if font:
            r_pr = OxmlElement("w:rPr")
            r_fonts = OxmlElement("w:rFonts")
            r_fonts.set(qn("w:ascii"), font)
            r_fonts.set(qn("w:hAnsi"), font)
            r_pr.append(r_fonts)
            level.append(r_pr)
        abstract.append(level)
        numbering.append(abstract)

        num = OxmlElement("w:num")
        num.set(qn("w:numId"), str(num_id))
        abstract_ref = OxmlElement("w:abstractNumId")
        abstract_ref.set(qn("w:val"), str(abstract_id))
        num.append(abstract_ref)
        numbering.append(num)

    make_numbering(next_abstract, next_num, "bullet", "•", "Symbol")
    make_numbering(next_abstract + 1, next_num + 1, "decimal", "%1.")
    reference_num = OxmlElement("w:num")
    reference_num.set(qn("w:numId"), str(next_num + 2))
    abstract_ref = OxmlElement("w:abstractNumId")
    abstract_ref.set(qn("w:val"), str(next_abstract + 1))
    reference_num.append(abstract_ref)
    level_override = OxmlElement("w:lvlOverride")
    level_override.set(qn("w:ilvl"), "0")
    start_override = OxmlElement("w:startOverride")
    start_override.set(qn("w:val"), "1")
    level_override.append(start_override)
    reference_num.append(level_override)
    numbering.append(reference_num)
    return next_num, next_num + 1, next_num + 2


def apply_num(paragraph, num_id):
    p_pr = paragraph._p.get_or_add_pPr()
    num_pr = OxmlElement("w:numPr")
    ilvl = OxmlElement("w:ilvl")
    ilvl.set(qn("w:val"), "0")
    num = OxmlElement("w:numId")
    num.set(qn("w:val"), str(num_id))
    num_pr.extend([ilvl, num])
    p_pr.append(num_pr)


def add_bullet(doc, text):
    paragraph = doc.add_paragraph()
    apply_num(paragraph, doc._bullet_num_id)
    paragraph.add_run(text)
    return paragraph


def add_number(doc, text):
    paragraph = doc.add_paragraph()
    apply_num(paragraph, doc._decimal_num_id)
    paragraph.add_run(text)
    return paragraph


def add_body(doc, text, bold_lead=None):
    paragraph = doc.add_paragraph(style="Normal")
    if bold_lead and text.startswith(bold_lead):
        paragraph.add_run(bold_lead).bold = True
        paragraph.add_run(text[len(bold_lead):])
    else:
        paragraph.add_run(text)
    return paragraph


def add_callout(doc, label, text, tone="normal"):
    paragraph = doc.add_paragraph(style="Callout")
    label_run = paragraph.add_run(f"{label}: ")
    set_run_font(label_run, size=10, color=RED if tone == "risk" else DARK_BLUE, bold=True)
    text_run = paragraph.add_run(text)
    set_run_font(text_run, size=10, color=INK)
    return paragraph


def add_code(doc, text):
    paragraph = doc.add_paragraph(style="Code Block")
    run = paragraph.add_run(text)
    set_run_font(run, name="Courier New", size=8.2, color=INK)
    return paragraph


def configure_styles(doc):
    styles = doc.styles
    normal = styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(11)
    normal.font.color.rgb = rgb(INK)
    normal._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    normal._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    normal.paragraph_format.space_before = Pt(0)
    normal.paragraph_format.space_after = Pt(6)
    normal.paragraph_format.line_spacing = 1.10
    normal.paragraph_format.widow_control = True

    title = styles["Title"]
    title.font.name = "Calibri"
    title.font.size = Pt(30)
    title.font.bold = True
    title.font.color.rgb = rgb(NAVY)
    title._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    title._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    title.paragraph_format.space_before = Pt(0)
    title.paragraph_format.space_after = Pt(8)
    title_p_pr = title.element.get_or_add_pPr()
    title_border = title_p_pr.find(qn("w:pBdr"))
    if title_border is not None:
        title_p_pr.remove(title_border)

    subtitle = styles["Subtitle"]
    subtitle.font.name = "Calibri"
    subtitle.font.size = Pt(15)
    subtitle.font.color.rgb = rgb(DARK_BLUE)
    subtitle._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
    subtitle._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
    subtitle.paragraph_format.space_after = Pt(8)

    for style_name, size, color, before, after in (
        ("Heading 1", 16, BLUE, 16, 8),
        ("Heading 2", 13, BLUE, 12, 6),
        ("Heading 3", 12, DARK_BLUE, 8, 4),
    ):
        style = styles[style_name]
        style.font.name = "Calibri"
        style.font.size = Pt(size)
        style.font.bold = True
        style.font.color.rgb = rgb(color)
        style._element.rPr.rFonts.set(qn("w:ascii"), "Calibri")
        style._element.rPr.rFonts.set(qn("w:hAnsi"), "Calibri")
        style.paragraph_format.space_before = Pt(before)
        style.paragraph_format.space_after = Pt(after)
        style.paragraph_format.keep_with_next = True
        style.paragraph_format.widow_control = True
    styles["Heading 1"].paragraph_format.page_break_before = True

    for name in ("Table Caption", "Table Citation", "Code Block", "Callout", "Contents Title", "TOC Entry"):
        if name not in styles:
            styles.add_style(name, 1)

    caption = styles["Table Caption"]
    caption.font.name = "Calibri"
    caption.font.size = Pt(9)
    caption.font.bold = True
    caption.font.color.rgb = rgb(DARK_BLUE)
    caption.paragraph_format.space_before = Pt(6)
    caption.paragraph_format.space_after = Pt(4)
    caption.paragraph_format.keep_with_next = True

    citation = styles["Table Citation"]
    citation.font.name = "Calibri"
    citation.font.size = Pt(8)
    citation.font.italic = True
    citation.font.color.rgb = rgb(MUTED)
    citation.paragraph_format.space_before = Pt(4)
    citation.paragraph_format.space_after = Pt(4)

    code = styles["Code Block"]
    code.font.name = "Courier New"
    code.font.size = Pt(8.2)
    code.font.color.rgb = rgb(INK)
    code._element.rPr.rFonts.set(qn("w:ascii"), "Courier New")
    code._element.rPr.rFonts.set(qn("w:hAnsi"), "Courier New")
    code.paragraph_format.left_indent = Inches(0.18)
    code.paragraph_format.right_indent = Inches(0.18)
    code.paragraph_format.space_before = Pt(4)
    code.paragraph_format.space_after = Pt(8)
    code.paragraph_format.line_spacing = 1.0
    code.paragraph_format.keep_together = True
    p_pr = code.element.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:fill"), "F7F7F7")
    p_pr.append(shd)

    callout = styles["Callout"]
    callout.font.name = "Calibri"
    callout.font.size = Pt(10)
    callout.paragraph_format.left_indent = Inches(0.16)
    callout.paragraph_format.right_indent = Inches(0.08)
    callout.paragraph_format.space_before = Pt(6)
    callout.paragraph_format.space_after = Pt(8)
    callout.paragraph_format.line_spacing = 1.10
    callout_pr = callout.element.get_or_add_pPr()
    callout_shd = OxmlElement("w:shd")
    callout_shd.set(qn("w:fill"), CALLOUT)
    callout_pr.append(callout_shd)
    borders = OxmlElement("w:pBdr")
    left = OxmlElement("w:left")
    left.set(qn("w:val"), "single")
    left.set(qn("w:sz"), "18")
    left.set(qn("w:space"), "6")
    left.set(qn("w:color"), BLUE)
    borders.append(left)
    callout_pr.append(borders)

    contents = styles["Contents Title"]
    contents.font.name = "Calibri"
    contents.font.size = Pt(20)
    contents.font.bold = True
    contents.font.color.rgb = rgb(NAVY)
    contents.paragraph_format.space_before = Pt(8)
    contents.paragraph_format.space_after = Pt(14)
    contents.paragraph_format.keep_with_next = True

    toc_entry = styles["TOC Entry"]
    toc_entry.font.name = "Calibri"
    toc_entry.font.size = Pt(9.5)
    toc_entry.font.color.rgb = rgb(INK)
    toc_entry.paragraph_format.space_before = Pt(0)
    toc_entry.paragraph_format.space_after = Pt(2)
    toc_entry.paragraph_format.line_spacing = 1.0
    toc_entry.paragraph_format.tab_stops.add_tab_stop(Inches(6.3), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS)


def configure_section(section, first=False):
    section.page_width = Inches(8.5)
    section.page_height = Inches(11)
    section.top_margin = Inches(1)
    section.bottom_margin = Inches(1)
    section.left_margin = Inches(1)
    section.right_margin = Inches(1)
    section.header_distance = Inches(0.492)
    section.footer_distance = Inches(0.492)
    if first:
        return
    section.header.is_linked_to_previous = False
    section.footer.is_linked_to_previous = False
    header_p = section.header.paragraphs[0]
    header_p.paragraph_format.space_after = Pt(0)
    header_p.paragraph_format.tab_stops.add_tab_stop(Inches(6.5), WD_TAB_ALIGNMENT.RIGHT)
    left = header_p.add_run("SmartBank | Database Security Implementation")
    set_run_font(left, size=8.5, color=MUTED, bold=True)
    right = header_p.add_run("\tCT069-3-3")
    set_run_font(right, size=8.5, color=MUTED)

    footer_p = section.footer.paragraphs[0]
    footer_p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    footer_p.paragraph_format.right_indent = Inches(0.15)
    run = footer_p.add_run("Page ")
    set_run_font(run, size=8.5, color=MUTED)
    add_field(footer_p, "PAGE", "1")
    set_page_number_start(section, 1)


def add_cover(doc):
    section = doc.sections[0]
    configure_section(section, first=True)
    for _ in range(4):
        spacer = doc.add_paragraph()
        spacer.paragraph_format.space_after = Pt(10)

    kicker = doc.add_paragraph()
    kicker.alignment = WD_ALIGN_PARAGRAPH.CENTER
    kicker.paragraph_format.space_after = Pt(18)
    run = kicker.add_run("DATABASE SECURITY • GROUP ASSIGNMENT REPORT")
    set_run_font(run, size=10, color=GOLD, bold=True)

    title = doc.add_paragraph(style="Title")
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.add_run("SmartBank Malaysia")
    subtitle = doc.add_paragraph(style="Subtitle")
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    subtitle.add_run("Secure Database Architecture, Implementation and Verification")

    line = doc.add_paragraph()
    line.alignment = WD_ALIGN_PARAGRAPH.CENTER
    line.paragraph_format.space_before = Pt(14)
    line.paragraph_format.space_after = Pt(76)
    run = line.add_run("Confidentiality  |  Integrity  |  Availability")
    set_run_font(run, size=11, color=BLUE, bold=True)

    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    meta.paragraph_format.space_after = Pt(4)
    run = meta.add_run("CT069-3-3 Database Security")
    set_run_font(run, size=12, color=NAVY, bold=True)
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    meta.paragraph_format.space_after = Pt(4)
    run = meta.add_run("Microsoft SQL Server 17.0 | Enterprise Developer Edition")
    set_run_font(run, size=10, color=MUTED)
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = meta.add_run("Implementation verified 10 August 2026")
    set_run_font(run, size=10, color=MUTED)


def add_contents(doc):
    heading = doc.add_paragraph(style="Contents Title")
    heading.add_run("Contents")
    entries = [
        ("Overview", 2),
        ("Data Dictionary (including data classification)", 4),
        ("Authentication and user management", 6),
        ("Role Based Access Control", 7),
        ("Row Level Security", 8),
        ("View", 9),
        ("Encryption", 10),
        ("Data Masking (Static and Dynamic)", 11),
        ("Hashing and Anonymization", 12),
        ("Backup Strategy, Scheduled Backup, Restore and Recovery", 13),
        ("Audit Strategy and Audit Matrix", 15),
        ("Login/Logout Audit", 16),
        ("Data Manipulation Language Audit", 17),
        ("Data Definition Language Audit", 18),
        ("Permission Change Audit", 19),
        ("Test Method and Results", 20),
        ("Security Evaluation and Limitations", 21),
        ("Lecturer Demonstration Runbook", 22),
        ("Conclusion", 23),
        ("References", 24),
    ]
    for label, page in entries:
        toc = doc.add_paragraph(style="TOC Entry")
        toc.add_run(label)
        toc.add_run(f"\t{page}")
    spacer = doc.add_paragraph()
    spacer.paragraph_format.space_after = Pt(4)
    add_callout(
        doc,
        "Reading guide",
        "The report follows the rubric headings exactly. Evidence values are taken from the live deployment; file references point to the reproducible scripts in this repository.",
    )


def build_report():
    doc = Document()
    configure_styles(doc)
    bullet_id, decimal_id, reference_id = setup_numbering(doc)
    doc._bullet_num_id = bullet_id
    doc._decimal_num_id = decimal_id
    doc._reference_num_id = reference_id

    core = doc.core_properties
    core.title = "SmartBank Database Security Implementation Report"
    core.subject = "CT069-3-3 Database Security assignment"
    core.author = "SmartBank Database Security Consulting Team"
    core.keywords = "SQL Server, database security, RBAC, RLS, encryption, audit, backup, recovery"
    core.comments = "Generated from the verified SmartBank SQL implementation. Credentials are fictitious coursework values for an isolated demo environment."

    add_cover(doc)
    body_section = doc.add_section(WD_SECTION.NEW_PAGE)
    configure_section(body_section)
    add_contents(doc)

    doc.add_heading("Overview", level=1)
    add_body(
        doc,
        "SmartBank Malaysia requires a database that preserves customer privacy, prevents unauthorized or invalid change, and remains recoverable after failure. The supplied initial schema contained four basic tables but no authentication model, ownership enforcement, encryption, audit trail, or recovery strategy. This implementation redesigns the database as a defence-in-depth platform rather than adding isolated controls to the original structure [1]-[7].",
    )
    add_body(
        doc,
        "The solution was deployed to WIN-IE4NH3CFSS5\\MSSQLSERVER02 on SQL Server 17.0.1000.7, Enterprise Developer Edition. SmartBankDB uses FULL recovery and both SmartBankDB and SmartBankAnalyticsDB report TDE state 3 with AES-256 database encryption. The final validation sequence uses real SQL-authenticated connections for a DBA, two managers, two officers, two customers, and a security auditor.",
    )
    add_callout(
        doc,
        "Evidence boundary",
        "The technical controls and recovery drills are complete. SQL Server Agent recorded genuine scheduled backup successes on 10, 11 and 12 August 2026 with zero failed outcomes, satisfying the lecturer's three-consecutive-calendar-day requirement.",
        tone="success",
    )

    doc.add_heading("Initial design weaknesses", level=2)
    weaknesses = [
        ("No identity model", "Every table is globally addressable; no login-to-person mapping exists.", "Separate logins/users, PrincipalMap, role membership and disabled guest access."),
        ("No least privilege", "The design cannot distinguish DBA, manager, officer and customer actions.", "Deny-by-default core schemas with narrow views and stored-procedure grants."),
        ("No row ownership", "A customer or officer could read another person's data if SELECT were granted.", "RLS predicates bind ORIGINAL_LOGIN() to StaffID or CustomerID."),
        ("Plaintext sensitive data", "IC number, salary, phone and address are directly readable at rest.", "AES-256 column encryption, TDE and encrypted backups."),
        ("Weak relational integrity", "No foreign keys, status domains, amount rules or balance safeguards.", "PK/FK/UNIQUE/CHECK constraints, rowversion, transaction locks and validation."),
        ("Incomplete transaction semantics", "The original record has no owner, direction, counterparty, actor, correlation or balance proof.", "Append-only double-entry-like records with hash chaining and reconciliation."),
        ("No auditability", "Valid and invalid access, DML, DDL and permission changes are invisible.", "SQL Server Audit, immutable DML JSON and application outcome events."),
        ("No availability design", "No recovery model, schedule, encrypted media, verification or restore procedure.", "Automated full/differential/log backups, VERIFYONLY, retention, PITR and temporal repair."),
    ]
    add_table(doc, "Table 1. Initial weaknesses and implemented response", ["Weakness", "Risk", "Implemented response"], weaknesses, [1850, 3350, 4160], 8.3)

    doc.add_heading("Defence-in-depth architecture", level=2)
    layers = [
        ("Identity", "SQL login + database user + PrincipalMap", "Authenticates a real connection and binds it to a staff/customer identity."),
        ("Authorization", "RBAC, explicit DENY, API grants", "Limits each role to its assigned business operations."),
        ("Row/column protection", "RLS, views, DDM, AES columns", "Restricts records and reveals sensitive values only through controlled modules."),
        ("Integrity", "Constraints, atomic procedures, locks, rowversion, hash chain", "Prevents invalid states, race conditions and silent ledger tampering."),
        ("Detection", "Native Audit + DML/application audit", "Records successful and denied activity with identity, statement and before/after evidence."),
        ("Recovery", "Temporal history + encrypted full/diff/log chain", "Supports fast row repair, full restore and five-minute point-in-time recovery."),
    ]
    add_table(doc, "Table 2. Security control layers", ["Layer", "Primary control", "Security outcome"], layers, [1450, 3300, 4610], 8.5)

    doc.add_heading("CIA traceability", level=2)
    cia = [
        ("Confidentiality", "Authentication, RBAC, RLS, views, DDM, AES column encryption, TDE, encrypted backups, static masking", "Role scripts prove allowed and denied visibility; right users receive automatic decryption."),
        ("Integrity", "Constraints, module-only DML, transaction PIN, atomic locks, append-only ledger, SHA2-512 chain, immutable audit", "Ledger verification and balance reconciliation pass; direct changes fail."),
        ("Availability", "FULL recovery, Agent schedules, checksums, VERIFYONLY, retention, temporal history, PITR", "All jobs passed; encrypted restore, temporal repair and PITR drills succeeded."),
    ]
    add_table(doc, "Table 3. CIA requirement traceability", ["Objective", "Controls", "Live proof"], cia, [1500, 4700, 3160], 8.4)

    doc.add_heading("Implementation map", level=2)
    impl = [
        ("Foundation", "sql/00_environment.sql; 01_schema.sql; 06_seed_data.sql", "Databases, schemas, constrained temporal model, keys/TDE and sample data"),
        ("Confidentiality", "sql/02_cryptography.sql; 03_row_level_security.sql; 08_principals_and_permissions.sql", "Column crypto, RLS, users, roles, grants and denies"),
        ("Integrity/audit", "sql/04_audit_tables_and_triggers.sql; 05_api.sql; 07_native_audit.sql", "Controlled DML, hash chain, row audit and native audit"),
        ("Availability/proof", "sql/09_backup_automation.sql; 10_static_masking.sql; tests/demo/recovery", "Agent jobs, anonymized copy, role tests, encrypted restore and PITR"),
    ]
    add_table(doc, "Table 4. Repository implementation map", ["Area", "Primary scripts", "Purpose"], impl, [1700, 3500, 4160], 8.4)

    doc.add_heading("Data Dictionary (including data classification)", level=1)
    add_body(
        doc,
        "Classification uses four practical levels: Public, Internal, Confidential and Highly Confidential. Microsoft sensitivity labels are applied to the highest-risk production columns, while the dictionary extends classification to every business attribute. Ciphertext remains highly classified because it is reversible by an authorized key holder; hashing is treated as sensitive authentication material rather than anonymous data.",
    )

    core_dictionary = [
        ("core.Branch", "BranchID", "char(5), PK", "Internal", "Stable branch identifier; constrained reference target."),
        ("core.Branch", "BranchName, City", "nvarchar", "Internal", "Operational location details; unique branch name."),
        ("core.Staff", "StaffID", "char(6), PK", "Internal", "Staff identifier with S99999 format check."),
        ("core.Staff", "StaffName, Phone", "nvarchar/varchar", "Confidential", "Directory data visible to authenticated users through a restricted view."),
        ("core.StaffEmployment", "Position, BranchID", "varchar/char", "Confidential", "Employment role and location; RLS protected."),
        ("core.StaffEmployment", "SalaryCipher", "varbinary(512)", "Highly Confidential", "AES ciphertext; Microsoft label Financial / Critical."),
        ("core.Customer", "CustomerID", "char(6), PK", "Confidential", "Customer identity key with C99999 format check."),
        ("core.Customer", "CustomerName, Email", "nvarchar/varchar", "Confidential", "DDM partial/email masks; Email unique."),
        ("core.Customer", "ICNumberCipher", "varbinary(512)", "Highly Confidential", "AES ciphertext; National ID / Critical classification."),
        ("core.Customer", "PhoneCipher, AddressCipher", "varbinary", "Confidential", "AES ciphertext; Contact Info / High classification."),
        ("core.Customer", "Status", "varchar(12)", "Internal", "ACTIVE, SUSPENDED or CLOSED only."),
        ("core.Account", "AccountID, CustomerID", "varchar/char", "Confidential", "Account identity and owner foreign key."),
        ("core.Account", "AccountType, Status", "varchar", "Confidential", "Checked domains for product and lifecycle."),
        ("core.Account", "Balance", "decimal(19,2)", "Highly Confidential", "Non-negative financial value; Financial / Critical classification."),
        ("core.Account", "RowVersion", "rowversion", "Internal", "Optimistic concurrency token."),
        ("core.TransactionRecord", "TransID, CorrelationID", "bigint/GUID", "Confidential", "Immutable event and multi-leg transaction correlation."),
        ("core.TransactionRecord", "CustomerID, AccountID, CounterpartyAccountID", "keys", "Highly Confidential", "Ownership and transfer relationship."),
        ("core.TransactionRecord", "Amount, Direction, Type, BalanceAfter", "decimal/varchar", "Highly Confidential", "Checked financial semantics and post-event balance."),
        ("core.TransactionRecord", "ActorLogin, Channel, TransDate", "sysname/varchar/datetime2", "Confidential", "Attribution and event context."),
        ("core.TransactionRecord", "PreviousHash, RecordHash", "varbinary(64)", "Highly Confidential", "SHA2-512 tamper-evident chain."),
    ]
    add_table(doc, "Table 5. Core business data dictionary", ["Table", "Column(s)", "Type/key", "Classification", "Definition and control"], core_dictionary, [1500, 1750, 1450, 1600, 3060], 7.7)

    support_dictionary = [
        ("sec.PrincipalMap", "LoginName, user type, StaffID/CustomerID, effective dates", "Highly Confidential", "Authoritative login-to-person mapping used by RLS and API checks."),
        ("sec.TransactionCredential", "Salt, PinHash, failure count, LockedUntil", "Highly Confidential", "32-byte random salt, 64-byte SHA2-512 hash and lockout state; PIN never stored."),
        ("audit.DmlAudit", "Actor/context, object, action, old/new JSON", "Highly Confidential", "Immutable detailed successful DML trail; encrypted PII/cipher secrets are excluded."),
        ("audit.ApplicationEvent", "Procedure outcome, safe error, target, correlation", "Confidential", "Logs both successful and failed controlled operations without raw PINs."),
        ("ops.BackupRun", "File, type, time, verified/succeeded, error", "Internal", "Operational evidence written by every backup procedure execution."),
        ("ops.RecoveryMarker", "UTC/server marker, expected rows JSON", "Internal", "Deterministic PITR target and expected recovery proof."),
        ("ops.LedgerChain", "LastTransID, LastHash", "Highly Confidential", "Singleton head of the append-only transaction chain."),
        ("history.*", "Previous temporal row versions", "Same as source", "System-managed evidence for time-based reconstruction."),
        ("demo.RecoveryTarget", "RecoveryID, EvidenceText, CreatedAt", "Internal", "Dedicated lecturer deletion/PITR demonstration data."),
        ("SmartBankAnalyticsDB.dbo.*Anon", "Random tokens, generalized bands, synthetic contact data", "Internal", "Irreversibly masked non-production analytics copy."),
    ]
    add_table(doc, "Table 6. Security, audit, operations and analytics dictionary", ["Object", "Key data", "Classification", "Purpose"], support_dictionary, [2150, 2950, 1700, 2560], 8.0)

    doc.add_heading("Authentication and user management", level=1)
    add_body(
        doc,
        "Each demonstration actor connects through a distinct SQL Server login and mapped database user. Password policy enforcement is enabled with CHECK_POLICY = ON; default database is SmartBankDB; guest CONNECT is revoked. Fictitious coursework passwords, recovery secrets and the transaction PIN are declared as SQLCMD variables in sql/deploy.sql for reproducible one-command setup; the supplied sa credential remains external. CHECK_EXPIRATION is disabled only to keep coursework demonstrations deterministic; a production identity service should enforce rotation or managed authentication.",
    )
    accounts = [
        ("sb_dba_aisha", "DBA", "S00003", "rl_authenticated, rl_dba"),
        ("sb_manager_daniel", "Manager", "S00001", "rl_authenticated, rl_manager"),
        ("sb_manager_siti", "Manager", "S00002", "rl_authenticated, rl_manager"),
        ("sb_officer_farid", "Officer", "S00004", "rl_authenticated, rl_officer"),
        ("sb_officer_priya", "Officer", "S00005", "rl_authenticated, rl_officer"),
        ("sb_customer_amelia", "Customer", "C00001", "rl_authenticated, rl_customer"),
        ("sb_customer_hafiz", "Customer", "C00002", "rl_authenticated, rl_customer"),
        ("sb_auditor_noor", "Auditor", "No business row", "rl_authenticated, rl_security_auditor; SmartBankAuditReader"),
    ]
    add_table(doc, "Table 7. Demonstration identities", ["Login/user", "Type", "Mapped identity", "Membership"], accounts, [2300, 1350, 1800, 3910], 8.2)
    identity_note = add_body(
        doc,
        "PrincipalMap includes active/effective-date checks so a disabled or expired mapping fails even when the SQL login still exists. ORIGINAL_LOGIN() is used instead of the mutable execution context, preserving the caller identity through EXECUTE AS OWNER procedures. The isolated coursework deployment deliberately commits fictitious role passwords, recovery passwords and the demonstration PIN for one-command setup; the supplied sa credential remains external and is never embedded.",
    )
    identity_note.paragraph_format.space_before = Pt(6)
    add_callout(doc, "Operational rule", "Disable both the server login and its PrincipalMap row during offboarding. Review role membership and effective dates together; neither layer replaces the other.")

    doc.add_heading("Role Based Access Control", level=1)
    add_body(
        doc,
        "RBAC is deny-by-default. public is denied direct SELECT/INSERT/UPDATE/DELETE on core and sec; ordinary roles receive only the views and procedures needed for their tasks. This prevents a broad table grant from bypassing procedure validation, DML outcome logging or column decryption policy.",
    )
    rbac = [
        ("DBA", "Own staff profile", "CREATE TABLE; ALTER/VIEW DEFINITION on core", "No base-table SELECT or business DML", "Maintains structure without managing data."),
        ("Manager", "Own + officers + DBA; all accounts/transactions", "Manage officer and DBA staff records; update own contact", "No peer-manager profile/change; no transactions or core DML", "Proves horizontal isolation within one role."),
        ("Officer", "Own staff; all accounts/transactions", "Create customers/accounts; change account status; own contact", "No manager functions; no balance DML; no transactions", "Manages customer accounts only."),
        ("Customer", "Own profile, accounts and transactions", "Deposit, withdrawal, transfer; set PIN", "No base tables; no other customer rows", "Only customers can transact."),
        ("Auditor", "Audit, metadata, backup health, masked analytics", "Read-only verification procedures", "No business tables or data changes", "Independent evidence access."),
    ]
    add_table(doc, "Table 8. RBAC permission matrix", ["Role", "Read scope", "Allowed change", "Explicit boundary", "Rationale"], rbac, [1150, 1900, 2400, 2050, 1860], 7.6)
    doc.add_heading("Permission precedence and controlled module model", level=2)
    add_body(
        doc,
        "The explicit schema DENY to rl_dba overrides its inherited public access, while controlled procedures execute as owner. Ownership chaining allows the procedure to reach protected tables; the caller still needs EXECUTE on that exact module and cannot reuse the owner's authority for ad hoc SQL. Procedures independently test ORIGINAL_LOGIN(), role type, row ownership, status, amount and PIN before any write.",
    )
    add_code(doc, "DENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::core TO public;\nGRANT EXECUTE ON OBJECT::api.usp_PerformTransaction TO rl_customer;\nDENY SELECT, INSERT, UPDATE, DELETE ON SCHEMA::core TO rl_dba;")

    doc.add_heading("Row Level Security", level=1)
    add_body(
        doc,
        "RLS filter predicates are schema-bound inline table-valued functions. They evaluate ORIGINAL_LOGIN() against sec.PrincipalMap and its active/effective-date controls [8]. StaffEmployment permits the caller's own row plus every BANK_OFFICER row for a manager, while excluding the other manager's confidential employment row. Customer, Account and TransactionRecord permit every row to managers/officers, but only the mapped CustomerID to a customer. DBA receives only its own profile through the API and has no broad business read grant.",
    )
    rls_rows = [
        ("StaffEmploymentSecurityPolicy", "core.StaffEmployment", "Staff ID and Position", "Own row plus officers; peer managers excluded"),
        ("CustomerDataSecurityPolicy", "core.Customer", "CustomerID", "Manager/officer see all; customer sees own"),
        ("CustomerDataSecurityPolicy", "core.Account", "CustomerID", "Manager/officer see all; customer sees own"),
        ("CustomerDataSecurityPolicy", "core.TransactionRecord", "CustomerID", "Manager/officer see all; customer sees own"),
    ]
    add_table(doc, "Table 9. RLS policies", ["Policy", "Protected table", "Predicate input", "Rule"], rls_rows, [2550, 2050, 1700, 3060], 8.3)
    add_code(doc, "CREATE SECURITY POLICY sec.CustomerDataSecurityPolicy\n  ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID) ON core.Customer,\n  ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID) ON core.Account,\n  ADD FILTER PREDICATE sec.fn_CustomerAccess(CustomerID) ON core.TransactionRecord\nWITH (STATE = ON, SCHEMABINDING = ON);")
    add_body(
        doc,
        "Filter predicates address reads. Direct writes are separately denied, and API procedures re-check ownership and business rules. This is intentional: RLS is one layer, not a substitute for write authorization. dbo is admitted only so owner-executed modules can complete; end users are never made dbo or db_owner.",
    )

    doc.add_heading("View", level=1)
    add_body(
        doc,
        "Views provide stable, minimal result sets and keep ciphertext, salts, hashes, audit internals and temporal period columns out of ordinary queries. They also compose naturally with RLS, so a customer's view returns only rows already admitted by the policy.",
    )
    views = [
        ("api.vw_StaffDirectory", "Staff, auditor, DBA (not customers)", "StaffID, name, phone", "No position, branch or salary; denied to rl_customer"),
        ("api.vw_StaffDirectoryPublic", "Customers", "Name, phone", "No StaffID, position, branch or salary"),
        ("api.vw_CustomerAccountSummary", "Managers, officers", "Customer, account type, balance, status", "No IC, phone/address ciphertext or PIN"),
        ("api.vw_MyAccounts", "Customers", "Own account summary", "RLS enforces owner"),
        ("api.vw_MyTransactions", "Managers, officers, customers", "Transaction statement fields", "Customer row filtering; no hashes"),
        ("audit.vw_DmlAudit", "Auditor", "Structured DML evidence", "No write permission"),
        ("audit.vw_AuditMatrix", "Auditor", "Event-to-control map", "Design evidence only"),
        ("api.vw_UserRoleMembership", "Auditor", "Users, roles and mapped identities", "No secret data"),
        ("api.vw_RolePermissionMatrix", "Auditor", "Explicit grants/denies", "No permission-change authority"),
    ]
    add_table(doc, "Table 10. Restricted views", ["View", "Consumer", "Exposes", "Withholds/control"], views, [2600, 1750, 2550, 2460], 8.1)

    doc.add_heading("Encryption", level=1)
    doc.add_heading("Column-level encryption and automatic decryption", level=2)
    add_body(
        doc,
        "A database master key protects SmartBank_ColumnEncryption_Certificate and its symmetric key. AES_256 encrypts salary, IC number, customer phone and address before storage. Only owner-executed procedures open the key and decrypt approved columns. api.usp_GetMyCustomerProfile first resolves ORIGINAL_LOGIN() to one CustomerID, then returns decrypted values for that row. Managers/officers receive only the business fields needed by their role; authenticated directory users never receive salary.",
    )
    add_code(doc, "OPEN SYMMETRIC KEY SmartBank_ColumnEncryptionKey\n  DECRYPTION BY CERTIFICATE SmartBank_ColumnEncryption_Certificate;\nSELECT CONVERT(nvarchar(30), DecryptByKey(ICNumberCipher)) AS ICNumber\nFROM core.Customer WHERE CustomerID = @MappedCustomerID;")
    add_body(
        doc,
        "The customer validation used a real sb_customer_amelia connection: the stored value remained varbinary ciphertext, but the controlled profile procedure automatically returned the expected fictitious plaintext. Another customer connection returned a different isolated row set.",
    )

    doc.add_heading("Transparent Data Encryption", level=2)
    add_body(
        doc,
        "Both SmartBankDB and SmartBankAnalyticsDB use database encryption keys with AES_256 protected by SmartBank_TDE_Certificate. Live state 3 means encrypted. TDE protects database and log pages at rest but does not implement row authorization or protect data returned to a permitted query, so it is combined with RBAC/RLS and column encryption [10].",
    )

    doc.add_heading("Encrypted backup media and key custody", level=2)
    add_body(
        doc,
        "Every full, differential and log backup explicitly specifies AES_256 and SmartBank_Backup_Certificate. Each file uses CHECKSUM and is followed by RESTORE VERIFYONLY. Certificate and private-key exports are produced for both TDE and backup encryption because a different instance cannot restore the media without the corresponding private certificates [11]. For this isolated coursework environment, the recovery passwords are deliberately declared in sql/deploy.sql for reproducible demonstration; they are fictitious and must not be reused.",
    )
    add_callout(doc, "Key custody", "For production, store certificate/private-key media separately from database backup media, restrict filesystem ACLs, maintain an offline escrow copy and test rotation/restoration under a documented dual-control procedure.")

    doc.add_heading("Data Masking (Static and Dynamic)", level=1)
    doc.add_heading("Dynamic Data Masking", level=2)
    add_body(
        doc,
        "CustomerName uses partial(1,\"XXXX\",1) and Email uses email(). A user with SELECT but no UNMASK receives transformed query results while the stored value remains unchanged [9]. Manager and officer validation showed masked values. DDM is deliberately treated as exposure reduction, not access control: Microsoft notes that inference remains possible for users with sufficiently broad ad hoc query access, so direct table access is denied and activity is audited.",
    )
    ddm = [
        ("core.Customer.CustomerName", "partial(1,\"XXXX\",1)", "Manager/officer summary", "Limits casual exposure while retaining recognizability"),
        ("core.Customer.Email", "email()", "Manager/officer summary", "Provides email-shaped masked output"),
        ("history.CustomerHistory equivalents", "Same functions", "Temporal queries", "Historical rows do not weaken masking"),
    ]
    add_table(doc, "Table 11. Dynamic masking rules", ["Column", "Function", "Consumer", "Purpose"], ddm, [2700, 2200, 1950, 2510], 8.3)

    doc.add_heading("Static masking and anonymization", level=2)
    add_body(
        doc,
        "SmartBankAnalyticsDB is a separate TDE-protected, SIMPLE-recovery analytics copy. Its nightly procedure creates fresh random customer, account, transaction and correlation tokens; generates synthetic .invalid emails; replaces phone numbers; derives non-identifying display names and regions; generalizes balances, amounts and dates into bands/buckets; and excludes IC numbers, addresses, salaries and source identifiers. Foreign-key relationships are preserved through temporary mapping tables, then the refresh commits atomically.",
    )
    static_rows = [
        ("Customer identity", "Random CUS token + 'Customer ####'", "Direct identifier removed"),
        ("Email/phone", "Synthetic example.invalid + XXX-XXX-0000", "No usable contact detail"),
        ("Account identity", "Random ACC token", "Joinability within snapshot only"),
        ("Balance/amount", "Business bands", "Reduces precision and re-identification risk"),
        ("Transaction date", "First day of month", "Month-level trend retained"),
        ("Correlation", "Random COR token", "Related transfer legs remain analyzable"),
    ]
    add_table(doc, "Table 12. Static anonymization transformations", ["Source concept", "Transformation", "Security effect"], static_rows, [2400, 3550, 3410], 8.4)
    add_body(
        doc,
        "The auditor is the only analytics reader and is explicitly denied INSERT, UPDATE, DELETE and ALTER on the analytics schema. A quality-check procedure asserts row counts and zero unsafe email, phone or display-name rows. The final SQL Agent run completed successfully.",
    )

    doc.add_heading("Hashing and Anonymization", level=1)
    add_body(
        doc,
        "Transaction PINs are one-way authentication material. Each customer receives a 32-byte CRYPT_GEN_RANDOM salt; HASHBYTES('SHA2_512', salt + normalized PIN bytes) produces a 64-byte hash [14]. The live metadata check confirmed both lengths. Five consecutive failures create a 15-minute lockout; successful verification resets the counter. PIN values and hashes are excluded from audit detail.",
    )
    add_code(doc, "SET @Salt = CRYPT_GEN_RANDOM(32);\nSET @PinHash = HASHBYTES('SHA2_512', @Salt + CONVERT(varbinary(32), @Pin));")
    add_body(
        doc,
        "SHA2-512 is also used for integrity, not secrecy. TransactionRecord.RecordHash commits the previous hash and canonical event fields, creating a tamper-evident sequence. api.usp_VerifyLedgerChain recomputes every link; api.usp_VerifyAccountBalances recomputes expected balances from the immutable transaction stream. Both checks passed after customer transactions.",
    )
    add_callout(doc, "Production strengthening", "For human-chosen credentials, a slow password KDF such as Argon2id, scrypt or PBKDF2 should be applied in the application tier. SQL Server HASHBYTES is retained here because the six-digit PIN is also rate-limited and the assignment requires an in-database hashing implementation.")

    doc.add_heading("Backup Strategy, Scheduled Backup, Restore and Recovery", level=1)
    add_body(
        doc,
        "SmartBankDB uses FULL recovery. The five-minute log interval defines an RPO of no more than five minutes during normal operation, assuming the log chain and backup target remain available. The design target RTO is 30 minutes for this coursework-sized database: import certificates where necessary, verify media, restore the latest full and differential, apply ordered logs with STOPAT, then run integrity/reconciliation checks. Actual production RTO must be measured against production data volume and infrastructure.",
    )
    schedule = [
        ("Full", "Daily 01:00", "Recovery base", "AES-256, compression, checksum, VERIFYONLY", "2 retries / 5 min"),
        ("Differential", "Every 6 hours from 06:00", "Shortens restore chain", "AES-256, compression, checksum, VERIFYONLY", "2 retries / 5 min"),
        ("Transaction log", "Every 5 minutes", "RPO <= 5 minutes", "AES-256, compression, checksum, VERIFYONLY", "2 retries / 2 min"),
        ("Static mask refresh", "Daily 03:00", "Fresh non-production data", "Atomic refresh + quality check", "2 retries / 5 min"),
        ("Retention", "Daily 04:30", "35-day scoped retention", "Deletes only .bak/.dif/.trn in configured SmartBank path", "1 retry / 10 min"),
    ]
    add_table(doc, "Table 13. SQL Server Agent schedule", ["Job", "Schedule", "Objective", "Control", "Retry"], schedule, [1500, 1850, 1750, 3100, 1160], 7.8)
    add_code(doc, "BACKUP LOG SmartBankDB TO DISK = @BackupFile\nWITH INIT, COMPRESSION, CHECKSUM,\nENCRYPTION (ALGORITHM = AES_256,\n  SERVER CERTIFICATE = SmartBank_Backup_Certificate);")

    doc.add_heading("Backup evidence", level=2)
    backup_evidence = [
        ("10 Aug 2026", "239", "0", "6 / 8 / 257", "271 / 271"),
        ("11 Aug 2026", "292", "0", "1 / 3 / 288", "292 / 292"),
        ("12 Aug 2026", "175", "0", "1 / 2 / 172", "175 / 175 through 14:15"),
    ]
    add_table(doc, "Table 14. Three-day scheduled backup evidence", ["Date", "Scheduled successes", "Failed outcomes", "Full / diff / log media", "Encrypted + checksummed"], backup_evidence, [1700, 1700, 1500, 2100, 2360], 8.2, "Source: live SQL Server Agent history and msdb backup metadata, 12 August 2026.")
    add_body(
        doc,
        "SQL Server Agent recorded genuine scheduled backup successes on 10, 11 and 12 August 2026 with zero failed outcomes: 239, 292 and 175 completed runs respectively. The corresponding media inventory contained 738 encrypted, checksummed backups across the three dates. Full backups ran daily, differential backups ran every six hours, and log backups ran every five minutes; the lower August 10 scheduled count reflects deployment after the 01:00 full-backup window. Every backup procedure performs RESTORE VERIFYONLY. Agent history capacity is 10,000 rows overall and 2,500 per job so the high-frequency log job cannot displace this evidence. sql/demo/03_backup_evidence.sql distinguishes scheduled from manual invocations and prints an explicit three-consecutive-date PASS verdict.",
    )

    doc.add_heading("Encrypted restore verification", level=2)
    add_body(
        doc,
        "The latest encrypted full backup passed RESTORE VERIFYONLY and was restored to SmartBankDB_RestoreValidation on the same instance. The restored copy was ONLINE with TDE state 3 and contained 6 staff, 12 customers, 18 accounts and 50 transaction rows. After opening the restored master key through the supplied recovery variables, an encrypted IC value decrypted correctly. This proves backup media integrity and database/key usability. sql/recovery/01_restore_encrypted_full.sql performs the same certificate import and validation sequence on a second instance; the separate-instance demonstration still requires a second instance address and server-side file paths.",
    )

    doc.add_heading("Point-in-time and temporal recovery", level=2)
    add_body(
        doc,
        "The PITR drill captured marker 0362E759-5A53-4050-B16F-E9214B51D5C6 at SQL Server-local 10 August 2026 03:33:34.288. Rows 1 and 2 were deleted from demo.RecoveryTarget and the DML audit captured both old values. An on-demand encrypted log backup closed the chain. SmartBankDB_PITR restored the latest eligible full, differential and ordered log backups with STOPAT 03:33:34.287 and returned all 10 rows while the source remained online. The source table was then returned to its 10-row clean state.",
    )
    add_body(
        doc,
        "A separate temporal drill changed customer C00012 to an accidental name/status, queried FOR SYSTEM_TIME AS OF the pre-change timestamp, and restored Zara Ibrahim / ACTIVE without a whole-database restore. SQL Server temporal tables keep previous row versions and support AS OF reconstruction [13]. PITR remains the authoritative option for broader failures [15].",
    )

    doc.add_heading("Audit Strategy and Audit Matrix", level=1)
    add_body(
        doc,
        "Audit uses three complementary stores. SQL Server Audit captures engine-observed success and failure at server/database scope; immutable DML triggers capture row-level before/after JSON for successful changes; application events capture controlled procedure outcomes and safe errors. This avoids claiming that a trigger can record a statement that never reached the table. The native file audit uses ON_FAILURE = FAIL_OPERATION and is readable by the auditor through the granular VIEW SERVER SECURITY AUDIT permission [12].",
    )
    audit_matrix = [
        ("Login success", "SUCCESSFUL_LOGIN_GROUP", "Native audit file", "Login, client IP, app, UTC time"),
        ("Login failure", "FAILED_LOGIN_GROUP", "Native audit file", "Failed principal, client IP, app, UTC time"),
        ("Logout", "LOGOUT_GROUP", "Native audit file", "Principal, session, resource totals, UTC time"),
        ("Successful DML", "Triggers + object actions", "DmlAudit + native file", "Actor, object, count, old/new JSON, transaction/correlation"),
        ("Denied/invalid DML", "SELECT/INSERT/UPDATE/DELETE + API outcome", "Native + ApplicationEvent", "Succeeded=0 statement or safe procedure error"),
        ("DDL", "DATABASE/SCHEMA_OBJECT_CHANGE_GROUP", "Native audit file", "CREATE/ALTER/DROP, actor and object"),
        ("User/role change", "DATABASE_PRINCIPAL_CHANGE_GROUP; DATABASE_ROLE_MEMBER_CHANGE_GROUP", "Native audit file", "User, role, statement and actor"),
        ("Permission change", "SCHEMA/DATABASE/SERVER_OBJECT_PERMISSION_CHANGE_GROUP", "Native audit file", "GRANT/DENY/REVOKE statement and actor"),
        ("Audit change", "AUDIT_CHANGE_GROUP", "Native audit file", "Audit configuration/tampering event"),
        ("Verification", "Ledger/balance/backup health", "Procedure result + native EXECUTE", "Integrity and availability status"),
    ]
    add_table(doc, "Table 15. Audit matrix", ["Event category", "Mechanism/action", "Evidence store", "Captured evidence"], audit_matrix, [1800, 2900, 1900, 2760], 7.8)
    add_callout(doc, "Privacy control", "Audit rows intentionally omit raw PINs, PIN hashes, salts, plaintext IC numbers, decrypted addresses and salary ciphertext. Evidence must be useful without becoming a second sensitive-data repository.")

    doc.add_heading("Login/Logout Audit", level=1)
    add_body(
        doc,
        "The server audit specification enables SUCCESSFUL_LOGIN_GROUP, FAILED_LOGIN_GROUP and LOGOUT_GROUP. Real connections are required: EXECUTE AS USER does not generate a server login event and would not prove SQL authentication, network address or ORIGINAL_LOGIN()-based policy behavior. The validation suite connected separately as every role, attempted an invalid password, and closed its pools. Live action codes LGIS, LGIF and LGO were observed in the audit file.",
    )
    login_tests = [
        ("Valid role login", "Distinct DBA/manager/officer/customer/auditor connection", "LGIS, succeeded=1, principal/app/client"),
        ("Invalid password", "Known demo login with wrong password", "LGIF, succeeded=0"),
        ("Disconnect", "Close each test connection", "LGO, principal/session/resource information"),
        ("Auditor read", "Execute audit.usp_ReadNativeAudit", "Allowed through SmartBankAuditReader only"),
    ]
    add_table(doc, "Table 16. Login/logout audit tests", ["Case", "Action", "Expected and observed evidence"], login_tests, [1900, 3200, 4260], 8.4)

    doc.add_heading("Data Manipulation Language Audit", level=1)
    add_body(
        doc,
        "AFTER triggers cover Staff, StaffEmployment, Customer, Account, TransactionRecord, PrincipalMap, TransactionCredential and the PITR demo table. They record UTC time, action, object, row count, ORIGINAL_LOGIN(), database user, application, host, client address, session, transaction ID, correlation ID and JSON old/new values. UPDATE and DELETE against DmlAudit and ApplicationEvent are blocked by immutable INSTEAD OF triggers.",
    )
    add_code(doc, "INSERT audit.DmlAudit (..., OldValues, NewValues)\nSELECT ...,\n  (SELECT StaffID, StaffName, Phone FROM deleted FOR JSON PATH),\n  (SELECT StaffID, StaffName, Phone FROM inserted FOR JSON PATH);")
    add_body(
        doc,
        "At the final evidence snapshot, DmlAudit contained 142 records: 61 INSERT, 68 UPDATE and 13 DELETE. Valid customer deposits produced Account updates plus append-only TransactionRecord inserts sharing a correlation ID. Denied direct table updates appeared in SQL Server Audit with succeeded=0. Procedure-level business failures such as an invalid PIN or insufficient funds appeared in ApplicationEvent with a safe error number/details.",
    )
    add_callout(doc, "Rollback boundary", "A table trigger's audit insert participates in the same transaction; SQL Server rolls it back when the statement/transaction rolls back. Native Audit is therefore the authoritative evidence for engine-denied or rolled-back statements, while ApplicationEvent records caught business-rule failures outside the failed transaction.")

    doc.add_heading("Data Definition Language Audit", level=1)
    add_body(
        doc,
        "DATABASE_OBJECT_CHANGE_GROUP and SCHEMA_OBJECT_CHANGE_GROUP record CREATE, ALTER and DROP operations with actor, object, statement, application and client context. The DBA test successfully created, altered and dropped core.DbaValidationProof while SELECT/INSERT on that table failed. This proves the assignment's unusual separation: the DBA can manage table definitions but cannot manage business data.",
    )
    ddl_tests = [
        ("CREATE TABLE core.DbaValidationProof", "Allowed for rl_dba", "CR action captured"),
        ("ALTER TABLE ... ADD ProofNote", "Allowed for rl_dba", "AL action captured"),
        ("INSERT/SELECT proof table", "Denied by schema DENY", "IN/SL succeeded=0"),
        ("DROP TABLE proof table", "Allowed for rl_dba", "DR action captured"),
    ]
    add_table(doc, "Table 17. DDL separation-of-duty proof", ["Statement", "Expected result", "Audit proof"], ddl_tests, [3850, 2500, 3010], 8.4)

    doc.add_heading("Permission Change Audit", level=1)
    add_body(
        doc,
        "The database audit specification includes database principal, database role membership, database object permission and schema object permission change groups. The schema-object group is essential for GRANT/REVOKE against tables and views. Server object permission and role membership groups cover server-scope changes. Deployment recreates the database specification idempotently so the declared action set cannot silently lag behind the script [16].",
    )
    perm_rows = [
        ("CR", "CREATE USER sb_demo_temporary_user", "Captured, actor sa"),
        ("APRL", "ALTER ROLE rl_authenticated ADD MEMBER", "Captured, actor sa"),
        ("G", "GRANT SELECT ON api.vw_StaffDirectory", "Captured, object api.vw_StaffDirectory"),
        ("R", "REVOKE SELECT ON api.vw_StaffDirectory", "Captured, object api.vw_StaffDirectory"),
        ("DPRL", "ALTER ROLE ... DROP MEMBER", "Captured, actor sa"),
        ("DR", "DROP USER sb_demo_temporary_user", "Captured, actor sa"),
    ]
    add_table(doc, "Table 18. Reversible permission-change evidence", ["Action ID", "Statement", "Observed proof"], perm_rows, [1400, 4650, 3310], 8.3, "Source: live SQL Server Audit at 2026-08-09 19:48:58 UTC.")
    add_body(
        doc,
        "sql/demo/04_permission_change.sql executes the six-step sequence and then reads the audit. It leaves no temporary user or permission behind. During the lecturer's spontaneous user/role change, the same audit reader can filter by timestamp, principal, object or statement.",
    )

    doc.add_heading("Test Method and Results", level=1)
    add_body(
        doc,
        "Testing is adversarial as well as functional. Each role script is run in a fresh authenticated connection; expected denials are treated as passing security results. Administrative checks inspect metadata for TDE, masking, RLS, schedules and encrypted backup properties. Integrity tests validate the transaction hash chain and recompute every account balance.",
    )
    tests = [
        ("Admin baseline", "TDE, data volume, RLS, DDM, jobs, encrypted backup", "Pass"),
        ("Ledger", "Recompute SHA2-512 chain and balances", "Pass"),
        ("DBA", "DDL allowed; base SELECT/DML and manager API denied", "Pass"),
        ("Managers Daniel/Siti", "Own + officer + DBA profiles; peer manager excluded from view/update/deactivation", "Implemented; live rerun required"),
        ("Officer", "Own profile; all account summaries; controlled account management", "Pass"),
        ("Customer Amelia", "Own decrypted profile/accounts/transactions; deposit; isolation", "Pass"),
        ("Customer Hafiz", "Different isolated account/transaction set", "Pass"),
        ("Auditor", "Audit/health/masked analytics; core business SELECT denied", "Pass"),
        ("Invalid login", "Wrong password creates FAILED_LOGIN_GROUP event", "Pass"),
        ("Native audit", "Recent valid/invalid access present", "Pass"),
        ("Audit persistence", "DML/application/native stores contain test evidence", "Pass"),
        ("Agent jobs", "Full, differential, log, static mask, retention", "Pass"),
        ("Encrypted restore", "VERIFYONLY + restored counts + PII decryption", "Pass (same instance)"),
        ("PITR", "Delete two rows; restore full/diff/log chain to marker", "Pass"),
        ("Temporal repair", "Accidental customer update restored from AS OF", "Pass"),
        ("Permission audit", "CREATE/role/GRANT/REVOKE/role/DROP", "Pass"),
    ]
    add_table(doc, "Table 19. Consolidated verification results", ["Test group", "Acceptance condition", "Result"], tests, [2150, 5710, 1500], 8.1)
    add_body(
        doc,
        "The retained pre-extension validation output was ALL 11 VALIDATION GROUPS PASSED and reported 6 staff, 12 customers, 18 accounts, 50 transactions, active RLS policies and two ONLINE validation databases: SmartBankDB_RestoreValidation and SmartBankDB_PITR. The second-manager extension adds Siti Aminah as staff S00002 and requires a fresh authenticated run of sql/tests/02_integrity/02_manager_staff_assertions.sql as both managers before the final evidence snapshot is presented.",
    )

    doc.add_heading("Security Evaluation and Limitations", level=1)
    strengths = [
        ("No single-control dependency", "Authentication, RBAC, RLS, API checks, encryption and auditing overlap."),
        ("Evidence-aware design", "Denials, successful row changes, procedure outcomes and recovery operations have distinct evidence paths."),
        ("Recovery is executable", "Scripts select the real msdb backup chain and prove recovered data instead of describing a hypothetical process."),
        ("Data minimization", "Views, masked analytics and audit redaction reduce unnecessary exposure."),
        ("Integrity beyond constraints", "Atomic locks, append-only transactions, hash chain and reconciliation detect logical/tampering errors."),
    ]
    add_table(doc, "Table 20. Design strengths", ["Strength", "Evaluation"], strengths, [2350, 7010], 8.5)
    limitations = [
        ("SQL authentication", "No MFA/federated lifecycle in this local coursework environment.", "Use Microsoft Entra/AD, MFA and a privileged access workflow."),
        ("Key storage", "Certificates/private keys and secrets are server/file based.", "Use HSM/Key Vault, dual control, rotation and separate escrow."),
        ("Single instance", "No automatic failover or off-site immutable copy.", "Add Availability Groups, off-site/object-locked backups and DR exercises."),
        ("DDM", "Can be inferred by a user with broad ad hoc query ability [9].", "Keep direct tables denied; monitor queries; use encryption/tokenization for true secrecy."),
        ("PIN hashing", "Fast SHA2 is weaker than a password KDF against offline guessing.", "Move verification to application KDF and retain server-side rate limits."),
        ("Audit files", "A sysadmin/OS administrator remains highly trusted.", "Ship audit to restricted/immutable SIEM storage and alert on audit changes."),
        ("RTO estimate", "30-minute target is not load-tested at production scale.", "Measure full-chain restore time on realistic data and hardware."),
        ("Three-day evidence", "Completed: scheduled backups succeeded on 10, 11 and 12 August 2026 with no failed outcomes.", "Preserve Agent and BackupRun history and show sql/demo/03_backup_evidence.sql during the demonstration."),
        ("Cross-instance proof", "Same-instance encrypted restore is complete; second instance connection not supplied.", "Import both certificates and run the supplied restore script on a second instance."),
    ]
    add_table(doc, "Table 21. Residual risks and improvements", ["Limitation", "Current exposure", "Recommended improvement"], limitations, [1900, 3550, 3910], 8.0)

    doc.add_heading("Lecturer Demonstration Runbook", level=1)
    add_body(doc, "Execute every proof in a fresh connection and run statements one by one so the permission boundary and its audit event are both visible.")
    steps = [
        "As sa, run sql/demo/01_security_inventory.sql. Show users, role membership, explicit grants/denies, RLS predicates, DDM metadata, TDE and Agent schedules.",
        "Connect as the DBA, both managers, both officers, both customers and auditor. Run the matching scripts under sql/tests. Explain that each EXPECTED DENIAL or EXPECTED VALIDATION FAILURE is a successful test.",
        "For the customer, call api.usp_GetMyCustomerProfile to show automatic decryption of that customer's encrypted values, then show another customer receives a different row set.",
        "Attempt one invalid password login. Run sql/demo/02_audit_evidence.sql and identify LGIS, LGIF and LGO plus the DML/application events from the role tests.",
        "Run sql/demo/03_backup_evidence.sql. Show the completed 10-12 August three-day proof, no failed BackupRun, AES-256/checksum metadata and Agent history.",
        "On a second SQL instance, copy the latest encrypted full backup plus both certificate/private-key pairs. Run sql/recovery/01_restore_encrypted_full.sql with that instance's paths and secret variables; show counts, TDE and decryption.",
        "For PITR, run 02_capture_pitr_marker.sql, let the lecturer delete row 1 and/or 2, run 03_capture_post_change_log.sql, then 04_restore_point_in_time.sql. Compare active and restored rows.",
        "If asked for a user or permission change, run sql/demo/04_permission_change.sql. Point to CR, APRL, G, R, DPRL and DR audit rows.",
        "Finish with sql/demo/05_consolidated_evidence.sql for a compact live state snapshot and the auditor's read-only evidence view.",
    ]
    for step in steps:
        add_number(doc, step)
    add_callout(doc, "Screen safety", "Do not display the sa password or the credential block at the top of sql/deploy.sql during the demo. Keep that section outside screen capture; the committed values exist only for this isolated coursework environment and must not be reused.", tone="risk")

    doc.add_heading("Conclusion", level=1)
    add_body(
        doc,
        "The implemented SmartBank database meets the assignment's confidentiality, integrity and availability requirements through layered, testable controls. Ordinary users never receive broad business-table access; identity-aware policies and controlled modules enforce each role's business scope. Sensitive data is encrypted at column, database and backup levels; dynamic and static masking reduce exposure; salted hashing and a transaction hash chain protect credentials and ledger integrity. Native and row-level auditing cover successful, denied, DML, DDL and permission activity. Automated encrypted backup jobs, temporal history, an encrypted restore and a successful point-in-time recovery establish a practical recovery path.",
    )
    add_body(
        doc,
        "The three-consecutive-day backup requirement is complete. The remaining external demonstration dependency is a second SQL instance for cross-instance encrypted restore proof; the repository contains the required certificate-import, restore and validation runbook.",
    )

    doc.add_heading("References", level=1)
    references = [
        ("CT069-3-3 Database Security Assignment brief", "Local course PDF supplied with the assignment."),
        ("Security Concepts", "Lecture 1, course material supplied."),
        ("Security Layers", "Lecture 2, course material supplied."),
        ("Security Vulnerabilities", "Lecture 3, course material supplied."),
        ("Data Protection", "Lecture 4, course material supplied."),
        ("Data Encryption", "Lecture 5, course material supplied."),
        ("Other Data Protection Techniques", "Lecture 6, course material supplied."),
        ("Microsoft Learn: Row-Level Security", "https://learn.microsoft.com/en-us/sql/relational-databases/security/row-level-security?view=sql-server-ver17"),
        ("Microsoft Learn: Dynamic Data Masking", "https://learn.microsoft.com/en-us/sql/relational-databases/security/dynamic-data-masking?view=sql-server-ver17"),
        ("Microsoft Learn: Transparent Data Encryption", "https://learn.microsoft.com/en-us/sql/relational-databases/security/encryption/transparent-data-encryption?view=sql-server-ver17"),
        ("Microsoft Learn: Backup encryption", "https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-encryption?view=sql-server-ver17"),
        ("Microsoft Learn: SQL Server Audit", "https://learn.microsoft.com/en-us/sql/relational-databases/security/auditing/sql-server-audit-database-engine?view=sql-server-ver17"),
        ("Microsoft Learn: Temporal tables", "https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal-tables?view=sql-server-ver17"),
        ("Microsoft Learn: HASHBYTES", "https://learn.microsoft.com/en-us/sql/t-sql/functions/hashbytes-transact-sql?view=sql-server-ver17"),
        ("Microsoft Learn: Restore to a point in time", "https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17"),
        ("Microsoft Learn: CREATE DATABASE AUDIT SPECIFICATION", "https://learn.microsoft.com/en-us/sql/t-sql/statements/create-database-audit-specification-transact-sql?view=sql-server-ver17"),
    ]
    for title, location in references:
        paragraph = doc.add_paragraph()
        apply_num(paragraph, doc._reference_num_id)
        if location.startswith("http"):
            add_hyperlink(paragraph, title, location)
        else:
            run = paragraph.add_run(title)
            run.bold = True
            paragraph.add_run(f". {location}")

    settings = doc.settings.element
    update_fields = settings.find(qn("w:updateFields"))
    if update_fields is None:
        update_fields = OxmlElement("w:updateFields")
        settings.append(update_fields)
    update_fields.set(qn("w:val"), "true")

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    build_report()
