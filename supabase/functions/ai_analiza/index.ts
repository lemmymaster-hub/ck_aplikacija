import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import pdfParse from "npm:pdf-parse@1.1.1";
import { Buffer } from "node:buffer";

serve(async (req) => {
  try {
    const body = await req.json();
    const javnaNabavkaId = body.javna_nabavka_id;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const nvidiaKey = Deno.env.get("NVIDIA_API_KEY");

    const { data: dokumenti, error } = await supabase
      .from("dokumenti_ponuda")
      .select("*")
      .eq("javna_nabavka_id", javnaNabavkaId)
      .eq("ekstenzija", "pdf");

    if (error) throw error;

    const analizaRezultati = [];

    for (const dokument of dokumenti) {
      const { data: fileData, error: downloadError } = await supabase.storage
  .from("dokumenti-ponuda")
  .download(dokument.storage_path);

if (downloadError || !fileData) {
  analizaRezultati.push({
    dokument: dokument.naziv_fajla,
    greska: "Dokument nije moguće preuzeti iz Supabase storage.",
    detalj: downloadError?.message ?? "",
  });

  continue;
}

const arrayBuffer = await fileData.arrayBuffer();

const prviBajtovi = new TextDecoder()
  .decode(new Uint8Array(arrayBuffer.slice(0, 5)));

if (!prviBajtovi.startsWith("%PDF")) {
  analizaRezultati.push({
    dokument: dokument.naziv_fajla,
    greska: "Preuzeti fajl nije pravi PDF. Moguće je da backend dobija HTML/grešku umjesto PDF fajla.",
    prvi_bajtovi: prviBajtovi,
  });

  continue;
}

      let tekstDokumenta = "";

try {
  const pdfData = await pdfParse(Buffer.from(arrayBuffer));
  tekstDokumenta = pdfData.text || "";
} catch (pdfError) {
  analizaRezultati.push({
    dokument: dokument.naziv_fajla,
    greska:
      "PDF nije moguće pročitati. Vjerovatno je skenirani dokument ili oštećen PDF.",
  });

  continue;
}

      if (tekstDokumenta.trim().length < 30) {
        analizaRezultati.push({
          dokument: dokument.naziv_fajla,
          greska: "PDF nema čitljiv tekst. Vjerovatno je skeniran dokument i treba OCR.",
        });
        continue;
      }

      const skraceniTekst = tekstDokumenta.substring(0, 18000);

      const prompt = `
Analiziraj stvarni tekst ponude ponuđača iz javne nabavke.

Vrati ISKLJUČIVO JSON, bez dodatnog teksta.

JSON format:
{
  "naziv_ponudjaca": "",
  "ukupna_cijena": "",
  "valuta": "",
  "pdv": "",
  "rok_isporuke": "",
  "garancija": "",
  "opis_ponude": "",
  "stavke": [
    {
      "naziv_stavke": "",
      "kolicina": "",
      "jedinicna_cijena": "",
      "ukupno": ""
    }
  ],
  "preporuka": "",
  "napomena": ""
}

Tekst dokumenta:
${skraceniTekst}
`;

      const nvidiaResponse = await fetch(
  "https://integrate.api.nvidia.com/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${nvidiaKey}`,
          },
          body: JSON.stringify({
            model: "meta/llama-3.3-70b-instruct",
            messages: [
              {
                role: "system",
                content:
                  "Ti si AI asistent za javne nabavke. Ne smiješ izmišljati podatke. Ako podatak ne postoji u dokumentu, napiši 'nije navedeno'.",
              },
              {
                role: "user",
                content: prompt,
              },
            ],
            temperature: 0.1,
          }),
        }
      );
console.log("NVIDIA STATUS:", nvidiaResponse.status);
   const nvidiaData = await nvidiaResponse.json();
console.log(JSON.stringify(nvidiaData));

let aiOdgovor = nvidiaData.choices?.[0]?.message?.content ?? "";

aiOdgovor = aiOdgovor
  .replace(/```json/g, "")
  .replace(/```/g, "")
  .trim();

let aiJson = null;

try {
  aiJson = JSON.parse(aiOdgovor);
} catch (_) {
  aiJson = {
    raw_response: aiOdgovor,
    greska: "AI odgovor nije validan JSON.",
  };
}

analizaRezultati.push({
  dokument: dokument.naziv_fajla,
  broj_karaktera_pdf_teksta: tekstDokumenta.length,
  ai_json: aiJson,
});
await supabase.from("ai_analize").insert({
  javna_nabavka_id: javnaNabavkaId,
  dokument_id: dokument.id,
  naziv_fajla: dokument.naziv_fajla,
  ai_json: aiJson,
  status: "uspjesno",
});
    }

    return new Response(
      JSON.stringify({
        success: true,
        broj_pdf_dokumenata: dokumenti.length,
        analiza: analizaRezultati,
      }),
      {
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({
        success: false,
        error: err.message,
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
});