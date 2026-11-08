# Acoustic Wave Derivation Pipeline: From First Principles to MATLAB

This document provides the complete, mathematically airtight 5-Level derivation of the acoustic pipe inspection system, bridging fundamental conservation laws to our automated MATLAB diagnostics.

---

## The 5-Level Derivation Architecture

```
[Level 1: Nature's Laws]
Newton's 2nd Law (Momentum) + Conservation of Mass (Compressibility)
                  │
                  ▼
[Level 2: The 1D Wave Equation & Traveling Wave Solutions]
d²p/dz² + k²p = 0
Solutions: p(z) = P⁺ e^(-jkz) + P⁻ e^(+jkz)
           U(z) = (1/Z₀) [ P⁺ e^(-jkz) - P⁻ e^(+jkz) ]
                  │
                  ▼
[Level 3: Acoustic Impedance & Energy Dissipation]
Z(z) = p(z) / U(z) = Rs + jXs
Rs = Friction / Viscous dissipation into heat (Porous Sand)
Xs = Elastic spring / inertia bounce delay
                  │
                  ▼
[Level 4: Obstacle Discontinuity at z = x]
Cross-sectional area bottleneck: S₁ = S₀(1 - α) ──► Z₁ = Z₀ / (1 - α)
Boundary matching (p and U continuity) yields:
R = (Z₁ - Z₀) / (Z₁ + Z₀) = α / (2 - α)
                  │
                  ▼
[Level 5: Automated MATLAB Diagnostics]
Interference of incident wave (P⁺) and reflected echo (P⁻) at Microphone:
1. Resonant Notch Spacing ──► Blockage Position: x = v / (2 Δf)
2. Resonant Notch Depth   ──► Physical Area Blocked: α = 2R / (1 + R)
```

---

## Level 1: Conservation Laws (The Nature Roots)

1. **Conservation of Momentum (Newton's 2nd Law for Fluid Particles)**:
   A spatial pressure difference accelerates air mass:
   $$\rho_0 \frac{\partial u}{\partial t} = -\frac{\partial p}{\partial z}$$
   where $\rho_0$ is ambient air density ($1.204\text{ kg/m}^3$) and $u(z,t)$ is air particle velocity.

2. **Conservation of Mass (Fluid Continuity & Compressibility)**:
   Compressing air into a smaller volume builds up internal pressure:
   $$\frac{\partial p}{\partial t} = -\rho_0 c^2 \frac{\partial u}{\partial z}$$
   where $c$ is the speed of sound ($346\text{ m/s}$ at $25^\circ\text{C}$).

---

## Level 2: 1D Wave Equation & Traveling Wave Solutions

Differentiating Newton's law with respect to $z$ and Mass Conservation with respect to $t$ eliminates particle velocity $u$, yielding the universal **1D Acoustic Wave Equation**:
$$\frac{\partial^2 p}{\partial z^2} = \frac{1}{c^2} \frac{\partial^2 p}{\partial t^2}$$

For a sinusoidal speaker excitation at angular frequency $\omega = 2\pi f$ (using phasor notation $\partial^2/\partial t^2 \to -\omega^2$), this simplifies to the **1D Helmholtz Equation**:
$$\frac{d^2 p}{dz^2} + k^2 p = 0 \quad \text{where wavenumber } k = \frac{\omega}{c} = \frac{2\pi}{\lambda}$$

### The Universal Solutions:
1. **Pressure Wave $p(z)$**:
   $$p(z) = \mathbf{P^+ e^{-jkz}} \text{ (Speaker Wave)} + \mathbf{P^- e^{+jkz}} \text{ (Reflected Echo)}$$
   - $e^{-jkz}$: Wave propagating forward (+z direction, away from speaker).
   - $e^{+jkz}$: Wave propagating backward (-z direction, toward microphone).

2. **Volume Velocity $U(z)$**:
   Derived directly by inserting $p(z)$ back into Newton's 2nd Law ($u = -\frac{1}{j\omega\rho_0}\frac{dp}{dz}$) and multiplying by duct cross-sectional area $S$:
   $$U(z) = S \cdot u(z) = \mathbf{\frac{1}{Z_0} \left(P^+ e^{-jkz} - P^- e^{+jkz}\right)}$$
   where $Z_0 = \frac{\rho_0 c}{S}$ is the **Characteristic Duct Impedance**.
   *(Note the minus sign on $P^-$: backward air velocity flows in the $-z$ direction).*

---

## Level 3: Acoustic Impedance ($Z = \frac{p}{U} = R_s + jX_s$)

Dividing the pressure wave by the volume velocity wave defines the total opposition to sound flow:
$$Z(z) = \frac{p(z)}{U(z)} = \frac{P_0}{U_0} e^{j\phi} = \mathbf{R_s + jX_s}$$
where $\phi = \phi_p - \phi_U$ is the phase difference between pressure and velocity.

1. **Acoustic Resistance ($R_s = \frac{P_0}{U_0}\cos\phi$) $\implies$ Viscous Heat Dissipation**:
   - In-phase component ($\phi = 0^\circ$).
   - Represents air particles rubbing against micro-pores between sand grains, converting acoustic energy irreversibly into heat.
2. **Acoustic Reactance ($X_s = \frac{P_0}{U_0}\sin\phi$) $\implies$ Elastic Energy Storage**:
   - $90^\circ$ out-of-phase component.
   - Represents air compressing like an elastic spring ($X_c = -\frac{1}{\omega C}$) and air mass inertia accelerating ($X_m = \omega M$).
   - Pure bounce with zero heat loss (smooth plastic bottle/rigid wall).

### Control Theory / Dynamic Systems Mapping:
- **Pressure ($p$) $\implies$ Potential Energy Storage**: $E_{\text{pot}} = \frac{1}{2} C_a p^2$ (Acoustic Capacitance / Spring).
- **Volume Velocity ($U$) $\implies$ Kinetic Energy Storage**: $E_{\text{kin}} = \frac{1}{2} M_a U^2$ (Acoustic Inertance / Moving Mass).
- **Resistance ($R_s$) $\implies$ Energy Dissipator / Damper**: $P_{\text{lost}} = U^2 R_s$.

---

## Level 4: Obstacle Discontinuity at $z = x$

When the sound wave traveling in a duct of area $S_0$ hits a blockage at $z = x$ that constricts the open area to $S_1 = S_0(1 - \alpha)$, the local impedance jumps:
$$Z_0 = \frac{\rho_0 c}{S_0} \quad \longrightarrow \quad Z_1 = \frac{\rho_0 c}{S_0 (1 - \alpha)} = \frac{Z_0}{1 - \alpha}$$

### Derivation of Reflection Coefficient $R$:
Matching pressure ($p_i + p_r = p_t \implies 1 + R = T$) and volume velocity ($U_i - U_r = U_t \implies \frac{1-R}{Z_0} = \frac{T}{Z_1}$) at the junction:
$$\frac{1 - R}{Z_0} = \frac{1 + R}{Z_1} \implies \mathbf{R = \frac{Z_1 - Z_0}{Z_1 + Z_0}}$$

Substituting $Z_1 = \frac{Z_0}{1 - \alpha}$:
$$R = \frac{\frac{Z_0}{1 - \alpha} - Z_0}{\frac{Z_0}{1 - \alpha} + Z_0} = \frac{\frac{1}{1-\alpha} - 1}{\frac{1}{1-\alpha} + 1} \implies \mathbf{R = \frac{\alpha}{2 - \alpha}}$$

Inverting to find physical area blockage $\alpha$ from measured reflection $R$:
$$\mathbf{\alpha = \frac{2R}{1 + R}}$$

---

## Level 5: Automated MATLAB Diagnostics Pipeline

At the co-located microphone ($z = 0$), the total acoustic pressure is the superposition of the outgoing wave and returning echo:
$$p_{\text{mic}}(f) = P^+ \left(1 + R \cdot e^{-j \frac{4\pi f x}{v}}\right)$$

The magnitude of the frequency response measured by MATLAB is:
$$|p_{\text{mic}}(f)| = |P^+| \sqrt{1 + R^2 + 2R\cos\left(\frac{4\pi f x}{v}\right)}$$

### The Two Automated Outputs:
1. **Blockage Position ($x$) via Resonant Comb Notches**:
   Cancellation valleys occur when $\cos\left(\frac{4\pi f x}{v}\right) = -1$ (destructive interference). The frequency spacing between consecutive valleys is:
   $$\Delta f_{\text{notch}} = \frac{v}{2x} \implies \mathbf{x = \frac{v}{2\,\Delta f_{\text{notch}}}}$$
2. **Physical Area Blockage ($\alpha\%$) via Valley Depth**:
   At the valley, measured amplitude drops to $|p_{\text{valley}}| = |P^+|(1 - R)$.
   Comparing to baseline clean amplitude ($A_{\text{base}} = |P^+|$):
   $$R = 1 - \frac{A_{\text{valley}}}{A_{\text{base}}} \implies \mathbf{\alpha = \frac{2R}{1 + R} \times 100\%}$$

---

## Physical Word Definitions for Quick Reference

- **Pressure Wave ($p$) $\implies$ "The Squeeze"**: Local compression and expansion of air relative to room pressure ($P_0 \cos(\omega t)$). The driving effort of sound.
- **Volume Velocity ($U$) $\implies$ "The Slosh"**: Actual physical volume rate of air molecules pumped through a duct slice ($\text{m}^3/\text{s}$). The resulting flow of sound.
- **Acoustic Impedance ($Z = p/U$) $\implies$ "The Pushback"**: Ratio of squeeze to flow. Tells you how stubbornly the pipe or sand resists sound motion.
- **Resonance $\implies$ "The Special Case"**: Discrete frequencies where mass inertia and spring compliance cancel ($X_s = 0$), or round-trip phase locks ($180^\circ$), collapsing into the deep diagnostic notch valleys used for detection.
