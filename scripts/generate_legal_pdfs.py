#!/usr/bin/env python3
"""Render the bundled FL-Tiya legal documents as deterministic PDFs."""

import argparse
import json
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "FLTiya" / "Resources"
PAGE_WIDTH, PAGE_HEIGHT = letter
LEFT = 54
RIGHT = PAGE_WIDTH - 54
WIDTH = RIGHT - LEFT
BOTTOM = 61
INK = HexColor("#182235")
MUTED = HexColor("#40526C")
TEAL = HexColor("#076557")
RULE = HexColor("#CFDCE4")
PALE = HexColor("#EDF6F4")
TEXT = ParagraphStyle("Body", fontName="Helvetica", fontSize=10.5, leading=14.7, textColor=INK)
NOTICE = ParagraphStyle("Notice", parent=TEXT, fontSize=10, leading=14.0, textColor=MUTED)
HEADING = ParagraphStyle("Heading", parent=TEXT, fontName="Helvetica-Bold", fontSize=12.5, leading=16)
LINKS = (
    ("Apple Standard EULA", "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"),
    ("Apple purchase refund help", "https://support.apple.com/en-us/118223"),
)
SPECS = (
    ("PrivacyPolicy.json", "privacy-policy.pdf", (4, 8), ()),
    ("UserAgreement.json", "user-agreement.pdf", (4, 8), LINKS),
)


def draw_text(pdf, value, x, y, size=10, *, color=INK, bold=False):
    pdf.setFillColor(color)
    pdf.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    pdf.drawString(x, y, value)


def draw_rule(pdf, y):
    pdf.setStrokeColor(RULE)
    pdf.setLineWidth(0.7)
    pdf.line(LEFT, y, RIGHT, y)


def draw_label(pdf, value, x, y):
    label = pdf.beginText(x, y)
    label.setFont("Helvetica-Bold", 9)
    label.setFillColor(TEAL)
    label.setCharSpace(1.4)
    label.textOut(value)
    label.setCharSpace(0)
    pdf.drawText(label)


def draw_paragraph(pdf, value, style, x, y, width):
    paragraph = Paragraph(value, style)
    _, height = paragraph.wrap(width, PAGE_HEIGHT)
    paragraph.drawOn(pdf, x, y - height)
    return y - height


def draw_brand_mark(pdf):
    pdf.setFillColor(TEAL)
    for step in range(3):
        x = LEFT + step * 7
        stripe = pdf.beginPath()
        stripe.moveTo(x, 738)
        stripe.lineTo(x + 4, 738)
        stripe.lineTo(x + 8, 748)
        stripe.lineTo(x + 4, 748)
        stripe.close()
        pdf.drawPath(stripe, fill=1, stroke=0)


def draw_title(pdf, document):
    draw_brand_mark(pdf)
    draw_label(pdf, "FL-TIYA  /  LEGAL", LEFT + 29, 739)
    draw_text(pdf, document["title"], LEFT, 698, 33, bold=True)

    status = (
        "Development draft - not yet effective"
        if document["status"] == "draft"
        else f'Effective: {document["effective_date"]}'
    )
    draw_text(pdf, status, LEFT, 673, 10.5, color=TEAL, bold=True)
    draw_text(pdf, "Contact:", LEFT, 655, 10.5, bold=True)
    contact = document["contact"]
    contact_x = LEFT + pdf.stringWidth("Contact:", "Helvetica-Bold", 10.5) + 8
    draw_text(pdf, contact, contact_x, 655, 10.5, color=TEAL)
    contact_width = pdf.stringWidth(contact, "Helvetica", 10.5)
    pdf.linkURL(f"mailto:{contact}", (contact_x, 652, contact_x + contact_width, 665), relative=0)

    y = 637
    inner_width = WIDTH - 24
    paragraph = Paragraph(escape(document["notice"]), NOTICE)
    _, height = paragraph.wrap(inner_width, PAGE_HEIGHT)
    pdf.setFillColor(PALE)
    pdf.rect(LEFT, y - height - 18, WIDTH, height + 18, fill=1, stroke=0)
    pdf.setFillColor(TEAL)
    pdf.rect(LEFT, y - height - 18, 2, height + 18, fill=1, stroke=0)
    paragraph.drawOn(pdf, LEFT + 12, y - height - 9)
    return y - height - 34


def draw_running_header(pdf, document):
    draw_brand_mark(pdf)
    draw_label(pdf, document["title"].upper(), LEFT + 29, 739)
    draw_rule(pdf, 727)
    return 706


def draw_footer(pdf, document, number, page_count):
    draw_rule(pdf, 49)
    draw_text(pdf, f'Version: {document["document_version"]}', LEFT, 32, 9, color=MUTED)
    pdf.setFont("Helvetica", 9)
    pdf.setFillColor(MUTED)
    pdf.drawRightString(RIGHT, 32, f"{number} / {page_count}")


def draw_document(source_path, output_path, splits, links):
    document = json.loads(source_path.read_text(encoding="utf-8"))
    if document["status"] not in ("draft", "effective"):
        raise ValueError(f"Unsupported document status: {source_path.name}")
    if (document["status"] == "effective") != bool(document["effective_date"]):
        raise ValueError(f"Effective date does not match status: {source_path.name}")
    boundaries = (0, *splits, len(document["sections"]))
    page_count = len(boundaries) - 1
    if any(start >= end for start, end in zip(boundaries, boundaries[1:])):
        raise ValueError(f"Page breaks do not match the section list: {source_path.name}")

    pdf = Canvas(str(output_path), pagesize=letter, invariant=1, pageCompression=1, lang="en")
    pdf.setTitle(document["title"])
    pdf.setAuthor("FL-Tiya")
    pdf.setSubject("Development draft" if document["status"] == "draft" else document["title"])
    for number, (start, end) in enumerate(zip(boundaries, boundaries[1:]), start=1):
        y = draw_title(pdf, document) if number == 1 else draw_running_header(pdf, document)
        for section in document["sections"][start:end]:
            y = draw_paragraph(pdf, escape(section["title"]), HEADING, LEFT, y, WIDTH) - 4
            y = draw_paragraph(pdf, escape(section["text"]), TEXT, LEFT, y, WIDTH) - 12
        if number == page_count and links:
            y = draw_paragraph(pdf, "Related Apple resources", HEADING, LEFT, y, WIDTH) - 5
            for title, url in links:
                label = f'<link href={quoteattr(url)} color="#076557"><u>{escape(title)}</u></link>'
                y = draw_paragraph(pdf, label, TEXT, LEFT, y, WIDTH) - 2
        if y < BOTTOM:
            raise ValueError(f"Page {number} would overflow: {source_path.name}; adjust the section breaks")
        draw_footer(pdf, document, number, page_count)
        pdf.showPage()
    pdf.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT / "supabase" / "legal")
    output_dir = parser.parse_args().output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    for source, filename, splits, links in SPECS:
        destination = output_dir / filename
        draw_document(SOURCE / source, destination, splits, links)
        print(destination)


if __name__ == "__main__":
    main()
