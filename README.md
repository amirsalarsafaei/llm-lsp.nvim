# LLM-LSP: Hybrid Neural-Classical Code Completion

## Abstract

LLM-LSP is an innovative code completion system that combines the power of Large Language Models (LLMs) with traditional Language Server Protocol (LSP) suggestions. This hybrid approach leverages probabilistic token selection to merge context-aware suggestions from neural models with statically analyzed completions from LSP servers.

## Introduction

Modern code completion systems typically fall into two categories:
1. Traditional static analysis-based completions (LSP)
2. Neural network-based suggestions (LLMs)

This project bridges these approaches by implementing a novel probability-weighted completion system that can utilize both sources simultaneously, potentially offering more accurate and contextually relevant suggestions.

## Technical Architecture

### Core Components

1. **Probability Integration System**
   - Implements Levenshtein distance-based similarity matching
   - Combines LLM token probabilities with LSP suggestion rankings
   - Uses configurable weights to balance between neural and classical suggestions

2. **LSP Integration**
   - Real-time LSP suggestion collection
   - Conversion of LSP rankings to probability space
   - Similarity threshold-based matching with LLM tokens

3. **LLM Interface**
   - Currently uses OpenAI's GPT-4 API (configurable)
   - Structured for easy adaptation to local models (e.g., Llama)
   - Streaming response handling for real-time completions

### Key Features

- Weighted probability combination algorithm
- Real-time streaming completions
- Configurable similarity thresholds
- Extensible architecture for multiple LLM backends
- Detailed logging system for debugging and analysis

## Implementation Details

### Probability Combination Algorithm


```lua
local lsp_weight = 0.3  -- Adjustable weight for LSP vs LLM balance
local similarity_threshold = 0.7  -- Minimum similarity score for matching
```

The system uses a weighted combination approach:
1. LSP suggestions are converted to a probability space
2. LLM token probabilities are preserved
3. Similarity matching identifies related suggestions
4. Final probabilities are computed using configurable weights

### Future Potential

1. **Local LLM Integration**
   - Integration with Llama and other local LLMs
   - Reduced latency and improved privacy
   - Custom fine-tuning possibilities

2. **Advanced Probability Models**
   - Bayesian integration of multiple suggestion sources
   - Dynamic weight adjustment based on context
   - Learning from user selections

3. **Performance Optimizations**
   - Caching mechanisms for frequent completions
   - Parallel processing of multiple suggestion sources
   - Optimized similarity matching algorithms

## Usage

1. Set up environment variables:
   ```bash
   export OPENAI_API_KEY="your-api-key"
   export OPENAI_API_URL="your-api-url"  # Optional, defaults to OpenAI endpoint
   ```

2. In Neovim:
   ```vim
   :AIAssist
   ```

## Research Applications

This project serves as a proof of concept for:
1. Hybrid neural-classical code completion systems
2. Probability-based integration of multiple suggestion sources
3. Real-time streaming completion in editor environments

## Contributing

Contributions are welcome, particularly in the following areas:
- Integration with additional LLM backends
- Improved probability combination algorithms
- Performance optimizations
- Documentation and testing

## License

[MIT License](LICENSE)

## Citation

If you use this work in your research, please cite:

```bibtex
@software{llm_lsp,
  title = {LLM-LSP: Hybrid Neural-Classical Code Completion},
  author = {Amirsalar Safaei Ghaderi},
  year = {2024},
  url = {https://github.com/amirsalarsafaei/llm-lsp.nvim}
}
```
