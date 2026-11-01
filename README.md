# Any-Model Playground

Ek single-file chat UI jisme koi bhi model chal sakta hai: local Ollama (uncensored/abliterated), ya cloud providers jaise Groq, OpenRouter, Claude, Gemini, OpenAI.

Koi backend nahi, koi login nahi, koi account nahi. API keys sirf tumhare browser ke `localStorage` me rehti hain.

## Live

https://bittubuilds.github.io/any-model-playground/

## Local Ollama setup

```bash
ollama pull eriktonon/qwen3.8-uncensored:9b
```

Lambi chat ke liye context badhao (default chhota hota hai):

```bash
# macOS / Linux
export OLLAMA_CONTEXT_LENGTH=32768

# Windows
setx OLLAMA_CONTEXT_LENGTH 32768
```

CORS error aaye to:

```bash
export OLLAMA_ORIGINS="*"
```

Phir Ollama restart karo. Page sidebar me **Detect models** dabao, tumhare pulled models list ho jayenge.

## Local se kholna (sabse reliable)

```bash
python3 -m http.server 8000
# browser: http://localhost:8000/index.html
```

**Important:** GitHub Pages HTTPS pe hota hai, aur Chrome HTTPS page se `http://localhost:11434` block kar deta hai (Private Network Access). Local Ollama ke liye page ko local se kholo:

```bash
python3 -m http.server 8000
# browser: http://localhost:8000/index.html
```

Deployed Pages URL cloud providers (Groq, OpenRouter, Anthropic, Gemini) ke liye hai.

## GitHub Codespaces (model cloud me chalta hai, laptop pe kuch nahi)

Repo me devcontainer ready hai. Model codespace ke andar download hota hai, tumhare localhost pe nahi.

1. Repo kholo -> **Code -> Codespaces -> Create codespace on main**. Free 2-core / 8 GB machine kaafi hai.
2. Pehli baar `scripts/start-ollama.sh` khud chalta hai: Ollama install, `ollama serve`, model pull. (Manual: `bash scripts/start-ollama.sh`.)
3. **Ports** tab -> port **11434** -> visibility **Public**.
4. Us port ka URL copy karo, shape: `https://<codespace-name>-11434.app.github.dev`
5. Playground kholo, provider **Ollama**, Base URL me `<wo URL>/v1` paste karo, Model field me pulled model ka naam, Send.

Machine size ke hisaab se model:

| Codespace machine | RAM | Model |
|---|---|---|
| 2-core (free) | 8 GB | `s1gnature/gemma4-uncensored-mtp:e2b-q4_k_m` (3.6 GB) |
| 4-core | 16 GB | `s1gnature/gemma4-uncensored-mtp:e4b-q4_k_m` (6.5 GB) ya `eriktonon/qwen3.8-uncensored:9b` (6.3 GB) |
| 8-core+ | 32 GB | `abliterant/qwen3.8-rana:q4_K_M` (17.5 GB) |

Doosra model chahiye to:

```bash
OLLAMA_MODEL=eriktonon/qwen3.8-uncensored:9b bash scripts/start-ollama.sh
```

Dhyan rakho:

- Port public karne ka matlab, jis ke paas URL hai wo bhi model use kar sakta hai jab tak codespace chalu hai. Kaam khatam hone pe codespace **Stop** karo.
- Free tier: 120 core-hours/month (2-core = ~60 ghante chalu) aur 15 GB-month storage.
- Codespace stop/hibernate hone ke baad `postStartCommand` Ollama phir start kar deta hai, model disk pe rehta hai, dobara pull nahi hoga.
- Thinking models (gemma4, qwen3.8) apna reasoning "Thinking" panel me dikhate hain. Max tokens kam hua to jawab thinking me hi khatam ho sakta hai.

## Cloud providers (CORS)

Groq, OpenRouter, Anthropic aur Gemini browser se direct chalte hain. OpenAI, Mistral, DeepSeek, xAI browser CORS band rakhte hain, unke liye proxy chalao:

```bash
node proxy.mjs
# Base URL field: http://localhost:8787/https://api.openai.com/v1
```

## Uncensored models in the picker

| Model | Size | Note |
|---|---|---|
| `eriktonon/qwen3.8-uncensored:9b` | 6.3 GB | default, abliterated, 256K ctx, vision |
| `eriktonon/qwen3.8-uncensored:27b` | 17 GB | bada bhai |
| `s1gnature/gemma4-uncensored-mtp:e4b-q4_k_m` | 6.5 GB | 0/465 refusals claim, fast |
| `s1gnature/gemma4-uncensored-mtp:e2b-q4_k_m` | 3.6 GB | sabse halka |
| `abliterant/qwen3.8-rana:q4_K_M` | 17.5 GB | documented refusal ablation, 16GB+ VRAM |
| `abliterant/qwen3.8-rana:q3_K_M` | 14.2 GB | ~16GB machine ke liye |
| `mgraffam/qwen3.8-EfficientThink-uncensored:27b` | 20 GB | thinking model |
| `dolphin-mistral:latest` | 4.1 GB | classic uncensored |
| `dolphin-mixtral:8x7b` | 26 GB | MoE classic |
| `llama2-uncensored:7b` | 3.8 GB | purana classic |

Ye open-weight, refusal-ablated models hain. Inke andar koi hosted safety layer nahi hoti, isliye output ka zimma tumhara hai.
