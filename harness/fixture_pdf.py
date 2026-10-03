"""Original benign PDF fixture; no external files, scripts, or embedded content."""
from pathlib import Path
import sys

def make_pdf(path: Path, pages: int = 1):
    objects = []
    def add(body: bytes):
        objects.append(body)
        return len(objects)
    add(b'<< /Type /Catalog /Pages 2 0 R >>')
    page_ids = [3 + index * 2 for index in range(pages)]
    add(b'<< /Type /Pages /Count ' + str(pages).encode() + b' /Kids [' + b' '.join(f'{i} 0 R'.encode() for i in page_ids) + b'] >>')
    for index in range(pages):
        color = b'1 0 0' if pages == 1 else b'0 0 1'
        stream = color + b' rg 40 40 120 120 re f\n'
        add(f'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents {4 + index * 2} 0 R >>'.encode())
        add(b'<< /Length ' + str(len(stream)).encode() + b' >>\nstream\n' + stream + b'endstream')
    data = bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
    offsets = [0]
    for index, body in enumerate(objects, 1):
        offsets.append(len(data))
        data.extend(f'{index} 0 obj\n'.encode() + body + b'\nendobj\n')
    xref = len(data)
    data.extend(f'xref\n0 {len(offsets)}\n0000000000 65535 f \n'.encode())
    data.extend(b''.join(f'{offset:010} 00000 n \n'.encode() for offset in offsets[1:]))
    data.extend(f'trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)

if __name__ == '__main__':
    make_pdf(Path(sys.argv[1]), int(sys.argv[2]) if len(sys.argv) > 2 else 1)
