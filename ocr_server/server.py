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

    full_text = ""

    for i, image in enumerate(images):
        temp_path = os.path.join(tempfile.gettempdir(), f"easyocr_page_{i}.jpg")
        image.save(temp_path, "JPEG")

        result = reader.readtext(temp_path, detail=0, paragraph=True)

        for text in result:
            full_text += text + "\n"

    return {
        "success": True,
        "pages": len(images),
        "text": full_text
    }