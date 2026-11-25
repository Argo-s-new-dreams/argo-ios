# Licenze di terze parti · Argo per iPhone

Argo usa questi componenti. Il testo completo delle licenze, quello mostrato nell'app in **Impostazioni › Informazioni › Licenze e riconoscimenti**, è in [`Argo/Risorse/LicenzeTerzeParti.txt`](Argo/Risorse/LicenzeTerzeParti.txt).

| Componente | Autore | Licenza | Cosa chiede |
|---|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Fluid Inference | Apache 2.0 | Copia della licenza nell'app |
| VBx (in FluidAudio) | — | Apache 2.0 | Copia della licenza |
| fastcluster (in FluidAudio) | Daniel Müllner, Google Inc. | BSD | Copyright e licenza nella documentazione |
| NemoTextProcessing (in FluidAudio) | Fluid Inference | Apache 2.0 (+ componenti Apache/MIT) | Copia della licenza |
| [pyannote speaker-diarization-community-1](https://huggingface.co/pyannote/speaker-diarization-community-1) | Hervé Bredin e autori di pyannote.audio | CC BY 4.0 | Attribuzione, link alla licenza, indicazione delle modifiche |
| [Conversione Core ML](https://huggingface.co/FluidInference/speaker-diarization-coreml) | Fluid Inference | CC BY 4.0 | Come sopra |
| [LiteRT-LM](https://github.com/google-ai-edge/LiteRT-LM) (Argo Live, laboratorio) | Google LLC | Apache 2.0 | Copia della licenza nell'app |
| [Gemma 4 E2B](https://huggingface.co/google/gemma-4-E2B-it) in [formato LiteRT-LM](https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm) (Argo Live, laboratorio) | Google DeepMind | Apache 2.0 | Copia della licenza; scaricato da Hugging Face solo su richiesta |

Speech, Vision e Foundation Models sono framework di iOS e non richiedono attribuzione.

**Quando aggiungi una dipendenza o un modello:** aggiorna questa tabella e `LicenzeTerzeParti.txt`. Se aggiorni FluidAudio, ricontrolla la sua cartella `ThirdPartyLicenses`.
