# Acoustic Wave Analysis System

A MATLAB-based batch processing tool designed to extract fundamental acoustic properties from experiment audio recordings (`.mp3` and `.wav`). 

The system automates file discovery across trial folders and generates four core acoustic representations per audio file:
1. **Amplitude vs Time**: Raw sound pressure waveform envelope.
2. **Frequency Spectrum**: Single-sided FFT magnitude spectrum with plane-wave cut-off limit guide.
3. **Spectrogram**: Time-frequency power distribution resolving discrete stepped-frequency tones over time.
4. **Amplitude vs Dimensionless Distance**: Leading-edge time-gated acoustic pulse reflectometry ($\bar{x} = x/L$ from 0 to 1.15).

---

## Prerequisites

- **MATLAB**: Version R2019b or later recommended.
- **Required Toolboxes**:
  - `Signal Processing Toolbox` (required for the `spectrogram` function).
  - Base MATLAB covers `audioread`, `fft`, and graphics plotting.

---

## Directory Structure

Place audio recordings in the `mp3` folder organized by trial directories. The script reads this hierarchy and produces identical folder trees in `analyze`:

```text
FRA362-Acoustic-Wave-Analyze-System/
├── mp3/
│   ├── 2026-31-10-trial-a/
│   │   ├── 1.mp3 (or .wav)
│   │   └── 2.mp3
│   └── 2026-31-10-trial-b/
│       └── 1.mp3
│
├── analyze/                             <-- Generated automatically
│   ├── 2026-31-10-trial-a/
│   │   ├── 1/
│   │   │   ├── amplitude.svg / .fig
│   │   │   ├── frequency.svg / .fig
│   │   │   ├── spectrogram.svg / .fig
│   │   │   └── amplitude-distance.svg / .fig
│   │   └── 2/
│   │       └── ...
│   └── 2026-31-10-trial-b/
│       └── ...
│
├── AudioAnalyzer.m                      <-- Object-Oriented acoustic analysis class
├── main.m                               <-- Batch orchestration script
└── README.md
```

---

## Step-by-Step Usage Guide

### Step 1: Prepare Input Audio
Create a subfolder inside `mp3/` named after your trial (e.g., `mp3/2026-31-10-experiment-1/`). Place your recorded audio files inside, named consecutively (e.g., `1.mp3`, `2.mp3`, or `.wav`).

### Step 2: Configure Processing Parameters (Optional)
Open `main.m`. All major analysis parameters are located at the top of the file with explicit defaults:

```matlab
% Time & Frequency Windowing
TIME_RANGE  = [];    % Empty [] processes full duration (e.g., 10-20 seconds)
MAX_AMP     = [];    % Max amplitude limit on y-axis (empty = auto-scale)
MAX_FREQ    = 3000;  % Focus frequency plots up to 3000 Hz

% Spectrogram Resolution
WINDOW_LEN  = 1024;  % Window sample size (balances frequency vs time resolution)
OVERLAP_LEN = 512;   % Number of overlapping samples between segments
SAVE_FORMAT = 'svg'; % Static export format ('svg', 'png', etc.)
SAVE_FIG    = true;  % Save interactive MATLAB .fig files
```

### Step 3: Run Batch Analysis
Run `main.m` directly in the MATLAB Command Window or terminal:

```matlab
main
```

### Step 4: Review Outputs and Command Window Hyperlinks
During processing, the MATLAB Command Window prints clickable links to inspect results immediately:

```text
--- Processing trial [1/1]: 2026-31-10-trial-a (1 files) ---
  [OK] 1.mp3    -> 1-Click: [Amplitude] [Frequency] [Spectrogram] [Amp-Dist] | [Open Folder]
```

- Clicking **`[Amplitude]`**, **`[Frequency]`**, **`[Spectrogram]`**, or **`[Amp-Dist]`** opens the interactive MATLAB `.fig` file directly in a new figure window with mouse-wheel zoom and pan enabled.
- Clicking **`[Open Folder]`** reveals the export directory in Windows File Explorer.

---

## Output Visualizations

### 1. Amplitude vs Time (`amplitude.svg`)
Displays the raw time-domain signal. Useful for identifying signal start/stop boundaries, transient spikes, and steady-state envelope amplitudes.

![Amplitude vs Time](docs/example_plots/amplitude.svg)

### 2. Frequency Spectrum (`frequency.svg`)
Computes the single-sided FFT amplitude spectrum across the analyzed band. Displays resonance peaks, dominant modal frequencies, and harmonic distributions.

![Frequency Spectrum](docs/example_plots/frequency.svg)

### 3. Spectrogram (`spectrogram.svg`)
Computes short-time Fourier transforms to display power distribution across time and frequency. Clarifies discrete frequency steps, frequency drift, and localized acoustic attenuation.

![Spectrogram](docs/example_plots/spectrogram.svg)

### 4. Amplitude vs Dimensionless Distance (`amplitude-distance.svg`)
Extracts the initial leading-edge transit window ($t_0$ to $t_0 + 1.15 \cdot T_{\text{pipe}}$) across all frequency steps and maps time delay directly to dimensionless distance ($\bar{x} = x/L$). Clearly highlights the pipe entrance ($\bar{x} = 0.0$), blockage reflection peak ($\bar{x}_{\text{blockage}}$), and the open pipe end reflection ($\bar{x} = 1.0$). Faint background lines represent individual frequency steps, while the solid thick blue line represents the composite multitone average.

![Amplitude vs Dimensionless Distance](docs/example_plots/amplitude-distance.svg)

---

## Mathematical & Physical Formulations

The analysis pipeline applies the following acoustic formulations:

### 1. Acoustic Waveguide Cut-Off Frequency ($f_c$)
Ensures sound propagates purely as a one-dimensional **plane wave (Mode 0,0)** without higher-order cross-mode diagonal wall reflections or phase dispersion:
$$f_c \approx 0.586 \cdot \frac{v}{D}$$
For a laboratory pipe with diameter $D = 0.15\text{ m}$ (150 mm) and speed of sound $v = 346\text{ m/s}$:
$$f_c \approx 0.586 \times \frac{346}{0.15} \approx 1352\text{ Hz}$$
All discrete excitation tones are kept strictly below this frequency.

### 2. Characteristic Pipe Round-Trip Transit Time ($T_{\text{pipe}}$)
The time required for an acoustic wave to travel from the entrance to the pipe end ($L$) and return to the microphone:
$$T_{\text{pipe}} = \frac{2L}{v}$$
For a 2.0-meter pipe: $T_{\text{pipe}} = \frac{2 \times 2.0}{346} \approx 11.56\text{ ms}$.

### 3. Dimensionless Distance Normalization ($\bar{x}$)
Converts the leading-edge reflection time delay ($t - t_0$) into dimensionless distance ($\bar{x} = x/L$):
$$\bar{x} = \frac{x}{L} = \frac{v \cdot (t - t_0)}{2L} = \frac{t - t_0}{T_{\text{pipe}}}$$
- $\bar{x} = 0.00$: Speaker/microphone entrance.
- $\bar{x} = \bar{x}_{\text{blockage}}$: Known physical blockage location ($x_{\text{blockage}} / L$).
- $\bar{x} = 1.00$: Open pipe end reflection.

### 4. Amplitude Envelope via Hilbert Transform ($E(t)$)
Calculates the instantaneous upper amplitude boundary of the acoustic wave oscillations:
$$E(t) = \left| s(t) + j \cdot \mathcal{H}\{s(t)\} \right|$$
where $\mathcal{H}\{s(t)\}$ is the Hilbert transform of the acoustic signal $s(t)$.

### 5. Composite Multitone Stacking / Averaging ($\bar{E}(\bar{x})$)
Averages the extracted envelopes across all $K$ frequency steps ($k = 1, \dots, K$):
$$\bar{E}(\bar{x}) = \frac{1}{K} \sum_{k=1}^K E_k(\bar{x})$$
Physical reflections (entrance, blockage, pipe end) reinforce constructively across all frequencies, while non-physical ripples and random background noise cancel out.

### 6. Acoustic Dynamic Similitude (Helmholtz Number Scaling)
Preserves acoustic wave behavior between the laboratory model and full-scale sewer pipeline:
$$He = \frac{f \cdot L}{v} \implies f_{\text{model}} = f_{\text{real}} \times \left(\frac{L_{\text{real}}}{L_{\text{model}}}\right)$$
Testing at 300–1300 Hz in a 2.0-meter model directly represents the 50–216 Hz acoustic spectrum in a 12.0-meter real pipeline ($6\times$ scale factor).

---

## How the Benchmark Audio is Generated (`generate_dummy_data.m`)

The script synthesizes an 11-step `Step -> Stop -> Step -> Stop` acoustic experiment (300 Hz to 1300 Hz in 100 Hz steps) inside a 2-meter pipe ($L = 2.0\text{ m}$, $v = 346\text{ m/s}$).

Each frequency step runs for a **1.0-second total cycle**, broken into three distinct physical phases:

```text
|<--------------------------- 1.0 Second Cycle --------------------------->|
|-- 0 to 15 ms --|---------- 15 ms to 800 ms ----------|-- 800 to 1000 ms --|
  Leading Edge              Steady-State Tone                 Silence Gap
(Reflectometry)            (Resonance & FFT)              (Decay & Reset)
```

---

### Phase 1: Leading-Edge Pulse Transit (0 to 15 ms)
This phase models the initial travel of the sound down the pipe *before* standing waves develop, producing the clean reflection echoes used for distance plotting:

1. **Direct Wave Packet (Incident Sound at $x = 0$)**:
   The speaker fires an instant 2-cycle tone burst shaped by a Hann smoothing window:
   $$s_{\text{pulse}}(t) = 0.85 \sin(2\pi f_k t) \cdot \frac{1}{2}\left(1 - \cos\left(2\pi \frac{t}{T_{\text{pulse}}}\right)\right), \quad 0 \le t \le T_{\text{pulse}} = \frac{2}{f_k}$$

2. **Blockage Reflection Echo (Arrives at $t_{\text{block}}$)**:
   Sound travels to the blockage ($x_{\text{block}} = 0.8\text{ m}$) and reflects back to the microphone at round-trip time delay:
   $$t_{\text{block}} = \frac{2 \cdot x_{\text{block}}}{v} = \frac{2 \times 0.8\text{ m}}{346\text{ m/s}} = 4.62\text{ ms}$$
   The reflected wave packet is added with positive reflection amplitude:
   $$s_{\text{block}}(t) = +0.42 \cdot s_{\text{pulse}}(t - 4.62\text{ ms})$$

3. **Open Pipe End Reflection Echo (Arrives at $t_{\text{end}}$)**:
   Sound travels to the far end of the pipe ($L = 2.0\text{ m}$) and reflects back at round-trip time delay:
   $$t_{\text{end}} = \frac{2 \cdot L}{v} = \frac{2 \times 2.0\text{ m}}{346\text{ m/s}} = 11.56\text{ ms}$$
   Because an open pipe end creates acoustic pressure release, the reflected pulse is phase-inverted (negative):
   $$s_{\text{end}}(t) = -0.25 \cdot s_{\text{pulse}}(t - 11.56\text{ ms})$$
   *(In a clean pipe with no blockage, the end reflection is unattenuated at $-0.55$).*

---

### Phase 2: Steady-State Standing Wave (15 ms to 800 ms)
After 15 ms, sound waves have bounced back and forth multiple times, transitioning into a continuous acoustic standing wave. This continuous wave provides the data for the **Frequency Spectrum (FFT)** and **Spectrogram**:

- **Acoustic Wave Number**: $k = \frac{2\pi f_k}{v}$
- **Clean Pipe Standing-Wave Gain**:
  $$G_{\text{clean}}(f) = \frac{1}{|\sin(kL)| + 0.4}$$
- **Blocked Pipe Coupled-Cavity Gain**:
  The physical blockage constricts the pipe cross-section at $x_{\text{block}}$, dividing the pipe into two coupled acoustic chambers. This shifts the natural resonance frequencies and attenuates sound:
  $$G_{\text{blocked}}(f) = \frac{1}{\left|\sin(k x_{\text{block}}) + 0.5 \cos(k(L - x_{\text{block}}))\right| + 0.4}$$

The steady-state continuous tone is synthesized as:
$$s_{\text{steady}}(t) = 0.35 \cdot \left(\frac{G(f_k)}{2.5}\right) \cdot \sin(2\pi f_k t)$$

---

### Phase 3: Silence Gap (800 ms to 1000 ms)
The sound is set to zero for 200 ms ($0.2\text{ s}$):
$$s(t) = 0, \quad 800\text{ ms} \le t \le 1000\text{ ms}$$
This quiet window allows pipe reverberation to decay completely so the next frequency step starts with a clean zero baseline and a crisp, detectable onset ($t_0$).

---

### Background Noise Floor
Finally, realistic low-level ambient room/microphone noise is added across the recording:
$$s_{\text{final}}(t) = s(t) + 0.002 \cdot \mathcal{N}(0, 1)$$

---

## Programmatic OOP Usage

`AudioAnalyzer.m` can also be integrated into custom MATLAB scripts independently:

```matlab
% Instantiate analyzer
analyzer = AudioAnalyzer('mp3/my-trial/1.wav', ...
    'MaxFrequency', 3000, ...
    'WindowLength', 1024, ...
    'OverlapLength', 512, ...
    'SaveFormat', 'svg', ...
    'SaveFig', true);

% Run analysis and export plots to target folder
analyzer.analyzeAndExport('analyze/my-trial/1');
```
