import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import pdfParse from "npm:pdf-parse@1.1.1";
import { Buffer } from "node:buffer";

function ocistiAiOdgovor(text: string) {
  return (text || "")
    .replace(/```json/g, "")
    .replace(/```/g, "")
    .trim();
}

function nijeNavedeno(value: unknown) {
  const text = String(value ?? "").trim().toLowerCase();
  return text.length === 0 || text === "nije navedeno" || text === "null" || text === "undefined";
}

function prvaVrijednost(rezultati: any[], key: string) {
  const pronadjeno = rezultati.find((r) => !nijeNavedeno(r?.[key]));
  return pronadjeno?.[key] ?? "nije navedeno";
}

function podijeliTekstNaDijelove(tekst: string, maxDuzina = 5000) {
  const dijelovi = [];
  const cistTekst = (tekst || "").trim();

  for (let i = 0; i < cistTekst.length; i += maxDuzina) {
    dijelovi.push({
      page: dijelovi.length + 1,
      text: cistTekst.substring(i, i + maxDuzina),
    });
  }

  return dijelovi;
}

async function pozoviNvidiaAi(nvidiaKey: string, prompt: string) {
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
              "Ti si AI asistent za javne nabavke. Analiziraš samo tekst koji dobiješ. Ne smiješ izmišljati podatke. Ako podatak ne postoji u tekstu, napiši 'nije navedeno'. Vrati isključivo validan JSON.",
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

  if (!nvidiaResponse.ok) {
    throw new Error(
      `NVIDIA API greška ${nvidiaResponse.status}: ${JSON.stringify(nvidiaData)}`
    );
  }

  const aiOdgovor = ocistiAiOdgovor(
    nvidiaData.choices?.[0]?.message?.content ?? ""
  );

  try {
    return JSON.parse(aiOdgovor);
  } catch (_) {
    return {
      raw_response: aiOdgovor,
      greska: "AI odgovor nije validan JSON.",
    };
  }
}

serve(async (req) => {
  try {
    const body = await req.json();
    const javnaNabavkaId = body.javna_nabavka_id;

    if (!javnaNabavkaId) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Nedostaje javna_nabavka_id.",
        }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const nvidiaKey = Deno.env.get("NVIDIA_API_KEY");

    if (!nvidiaKey) {
      throw new Error("NVIDIA_API_KEY nije podešen u Supabase secrets.");
    }

    const { data: dokumenti, error } = await supabase
      .from("dokumenti_ponuda")
      .select("*")
      .eq("javna_nabavka_id", javnaNabavkaId)
      .eq("ekstenzija", "pdf");

    if (error) throw error;

    const analizaRezultati = [];

    for (const dokument of dokumenti ?? []) {
      console.log("DOKUMENT:", dokument.naziv_fajla);

      try {
        let stranice: Array<{ page: number; text: string }> = [];

        /*
          PRIORITET 1:
          Koristimo lokalni OCR po stranicama iz kolone ocr_pages_json.
          Ovo je novi MVP tok i rješava velike skenirane PDF dokumente.
        */
        if (
          Array.isArray(dokument.ocr_pages_json) &&
          dokument.ocr_pages_json.length > 0
        ) {
          stranice = dokument.ocr_pages_json
            .map((p: any, index: number) => ({
              page: Number(p.page ?? index + 1),
              text: String(p.text ?? ""),
            }))
            .filter((p: any) => p.text.trim().length > 20);

          console.log("KORISTIM OCR PAGES JSON:", stranice.length);
        }

        /*
          PRIORITET 2:
          Ako nema lokalnog OCR-a, pokušavamo pročitati ugrađeni tekst iz PDF-a.
          Ovo je za PDF dokumente exportovane iz Word-a.
        */
        if (stranice.length === 0) {
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

          const prviBajtovi = new TextDecoder().decode(
            new Uint8Array(arrayBuffer.slice(0, 5))
          );

          if (!prviBajtovi.startsWith("%PDF")) {
            analizaRezultati.push({
              dokument: dokument.naziv_fajla,
              greska:
                "Preuzeti fajl nije pravi PDF. Moguće je da backend dobija HTML/grešku umjesto PDF fajla.",
              prvi_bajtovi: prviBajtovi,
            });
            continue;
          }

          let tekstDokumenta = "";

          try {
            const pdfData = await pdfParse(Buffer.from(arrayBuffer));
            tekstDokumenta = pdfData.text || "";
          } catch (_) {
            tekstDokumenta = "";
          }

          if (tekstDokumenta.trim().length > 30) {
            stranice = podijeliTekstNaDijelove(tekstDokumenta, 5000);
            console.log("KORISTIM PDF TEXT CHUNKS:", stranice.length);
          }
        }

        /*
          PRIORITET 3:
          Stara kolona ocr_text ostaje samo kao fallback za ranije obrađene dokumente.
        */
        if (
          stranice.length === 0 &&
          dokument.ocr_text &&
          String(dokument.ocr_text).trim().length > 30
        ) {
          stranice = podijeliTekstNaDijelove(String(dokument.ocr_text), 5000);
          console.log("KORISTIM STARI OCR TEXT:", stranice.length);
        }

        if (stranice.length === 0) {
          analizaRezultati.push({
            dokument: dokument.naziv_fajla,
            greska:
              "Nema teksta za AI analizu. Pokreni lokalni OCR za ovaj dokument ili provjeri PDF.",
          });

          await supabase.from("ai_analize").insert({
            javna_nabavka_id: javnaNabavkaId,
            dokument_id: dokument.id,
            naziv_fajla: dokument.naziv_fajla,
            ai_json: null,
            status: "greska",
            greska:
              "Nema teksta za AI analizu. Pokreni lokalni OCR za ovaj dokument ili provjeri PDF.",
          });

          continue;
        }

        const rezultatiStranica = [];

        for (const stranica of stranice) {
          const brojStranice = stranica.page ?? rezultatiStranica.length + 1;
          const tekstStranice = String(stranica.text ?? "").trim();

          if (tekstStranice.length < 20) {
            continue;
          }

          const prompt = `
Analiziraj SAMO ovu jednu stranicu ponude iz javne nabavke.

VAŽNO:
- Vrati ISKLJUČIVO validan JSON.
- Ne piši markdown.
- Ne piši objašnjenje.
- Ne koristi \`\`\`.
- Ne izmišljaj podatke.
- Ako podatak ne postoji na ovoj stranici, napiši "nije navedeno".
- Ako na stranici vidiš tabelu/stavke/cijene, izvuci ih što preciznije.

JSON format:
{
  "stranica": ${brojStranice},
  "naziv_ponudjaca": "",
  "ukupna_cijena": "",
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
  "napomena": "",
  "preporuka": ""
}

Tekst stranice:
${tekstStranice}
`;

          const aiJson = await pozoviNvidiaAi(nvidiaKey, prompt);

          rezultatiStranica.push({
            stranica: brojStranice,
            ...aiJson,
          });
        }

        const sveStavke = [];

        for (const r of rezultatiStranica) {
          if (Array.isArray(r.stavke)) {
            for (const s of r.stavke) {
              if (
                s &&
                typeof s === "object" &&
                !nijeNavedeno(s.naziv_stavke)
              ) {
                sveStavke.push({
                  ...s,
                  stranica: r.stranica,
                });
              }
            }
          }
        }

        const finalniAiJson = {
          naziv_ponudjaca: prvaVrijednost(
            rezultatiStranica,
            "naziv_ponudjaca"
          ),
          ukupna_cijena: prvaVrijednost(rezultatiStranica, "ukupna_cijena"),
          pdv: prvaVrijednost(rezultatiStranica, "pdv"),
          rok_isporuke: prvaVrijednost(rezultatiStranica, "rok_isporuke"),
          garancija: prvaVrijednost(rezultatiStranica, "garancija"),
          opis_ponude: "Analiza je urađena po stranicama dokumenta.",
          stavke: sveStavke,
          broj_obradjenih_stranica: rezultatiStranica.length,
          analiza_po_stranicama: rezultatiStranica,
          napomena:
            "Rezultat je automatski generisan iz OCR/PDF teksta i treba ga provjeriti prije službene upotrebe.",
        };

        analizaRezultati.push({
          dokument: dokument.naziv_fajla,
          broj_stranica_za_ai: stranice.length,
          ai_json: finalniAiJson,
        });

        await supabase.from("ai_analize").insert({
          javna_nabavka_id: javnaNabavkaId,
          dokument_id: dokument.id,
          naziv_fajla: dokument.naziv_fajla,
          ai_json: finalniAiJson,
          status: "uspjesno",
        });
      } catch (documentError) {
        const poruka =
          documentError instanceof Error
            ? documentError.message
            : String(documentError);

        analizaRezultati.push({
          dokument: dokument.naziv_fajla,
          greska: poruka,
        });

        await supabase.from("ai_analize").insert({
          javna_nabavka_id: javnaNabavkaId,
          dokument_id: dokument.id,
          naziv_fajla: dokument.naziv_fajla,
          ai_json: null,
          status: "greska",
          greska: poruka,
        });
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        message: "AI analiza po stranicama je završena.",
        broj_pdf_dokumenata: dokumenti?.length ?? 0,
        analiza: analizaRezultati,
      }),
      {
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  } catch (err) {
    const poruka = err instanceof Error ? err.message : String(err);

    return new Response(
      JSON.stringify({
        success: false,
        error: poruka,
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
