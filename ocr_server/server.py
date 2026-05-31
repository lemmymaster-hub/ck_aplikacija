from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pdf2image import convert_from_bytes
import easyocr
import tempfile
import os

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

reader = easyocr.Reader(["en"], gpu=False)

@app.post("/ocr")
async def ocr_pdf(file: UploadFile = File(...)):
    content = await file.read()

    images = convert_from_bytes(
        content,
        dpi=350,
        poppler_path=r"C:\poppler\Library\bin"
    )

    pages_text = []

    for i, image in enumerate(images):
        temp_path = os.path.join(tempfile.gettempdir(), f"easyocr_page_{i}.jpg")
        image.save(temp_path, "JPEG")

        result = reader.readtext(temp_path, detail=0, paragraph=True)

        page_text = ""
        for text in result:
            page_text += text + "\n"

        pages_text.append({
            "page": i + 1,
            "text": page_text
        })

        try:
            os.remove(temp_path)
        except:
            pass

    return {
        "success": True,
        "pages": len(images),
        "pages_text": pages_text
    }