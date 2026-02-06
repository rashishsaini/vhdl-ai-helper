# VHDL AI Helper - Organized Project Structure

A comprehensive framework for AI-assisted VHDL hardware development with implementations of Cholesky decomposition and Newton-Raphson square root algorithms.

## Project Structure

```
vhdl-ai-helper/
│
├── cholesky-implementation/          # Cholesky 3×3 matrix decomposition
│   ├── README.md                     # Project-specific documentation
│   ├── sources/                      # VHDL source files (SOURCE OF TRUTH)
│   │   ├── code.vhd                  # Main Cholesky implementation
│   │   ├── sqrt_newton_xsim.vhd      # Newton-Raphson sqrt module
│   │   └── simple_cholesky_tb.vhd    # Testbench
│   ├── docs/                         # Implementation-specific documentation
│   │   ├── CHOLESKY_PERFORMANCE_ANALYSIS.md
│   │   ├── AGENT_INTEGRATION_GUIDE.md
│   │   ├── cholesky_xsim_solution.md
│   │   └── cholesky_fixes_applied.md
│   └── logs/                         # Simulation logs
│
├── newton-implementation/            # Newton-Raphson square root
│   ├── README.md                     # Project-specific documentation
│   ├── sources/                      # VHDL source files (SOURCE OF TRUTH)
│   │   ├── NewtonRaphson.vhd         # Core implementation
│   │   └── newton_tb.vhd             # Testbench
│   ├── docs/                         # Implementation-specific documentation
│   │   ├── newton_raphson_lessons.md
│   │   ├── xsim_fixed_point_issue.md
│   │   └── xsim_debugging_techniques.md
│   └── logs/                         # Simulation logs
│
├── cordic-sin-implementation/        # CORDIC sine/cosine algorithm
│   ├── sources/                      # Current stable implementation
│   │   ├── cordic_sin_module.vhd     # Main CORDIC module
│   │   └── cordic_sin_tb.vhd         # Testbench
│   └── vhdl_iterations/              # Design iteration history
│       ├── iteration_0/              # Initial combinatorial approach
│       ├── iteration_1/              # Sequential FSM version
│       ├── iteration_2/              # Handshake protocol version
│       └── iteration_3/              # Pipelined version
│
├── shared/                           # Shared resources across projects
│   ├── documentation/                # General documentation
│   │   ├── README_ANALYSIS.md
│   │   ├── EXECUTIVE_SUMMARY.txt
│   │   ├── PERFORMANCE_METRICS_SUMMARY.md
│   │   └── ANALYSIS_INDEX.txt
│   ├── learnings/                    # VHDL knowledge base (9 files, 128KB)
│   │   ├── LEARNINGS_INDEX.md        # ★ START HERE - Navigation guide
│   │   ├── CHOLESKY_PERFORMANCE_ANALYSIS.md (copied from cholesky-implementation/)
│   │   ├── AGENT_INTEGRATION_GUIDE.md (copied from cholesky-implementation/)
│   │   ├── cholesky_xsim_solution.md (copied from cholesky-implementation/)
│   │   ├── cholesky_fixes_applied.md (copied from cholesky-implementation/)
│   │   ├── newton_raphson_lessons.md (copied from newton-implementation/)
│   │   ├── xsim_debugging_techniques.md (copied from newton-implementation/)
│   │   ├── xsim_fixed_point_issue.md (copied from newton-implementation/)
│   │   └── COMPREHENSIVE_VHDL_XSIM_REFERENCE.md
│   ├── tools/                        # Automation tools
│   │   ├── vhdl_claude_helper.py
│   │   └── vhdl_iteration_orchestrator.py
│   ├── prompts/                      # Claude Code prompts
│   │   ├── claude_code_master_prompt.md
│   │   ├── claude_code_prompt_orchestrator.md
│   │   └── claude_code_prompt_realistic.md
│   └── scripts/                      # Testing & automation scripts
│       ├── *.tcl                     # Vivado TCL scripts
│       ├── *.sh                      # Shell scripts
│       └── logs/                     # Iteration logs
│
├── .claude/                          # Claude Code configuration
│   ├── commands/                     # Custom slash commands
│   │   ├── vhdl-master.md
│   │   ├── vhdl-orchestrator.md
│   │   └── vhdl-realistic.md
│   ├── agents/                       # Custom agent definitions
│   │   ├── vhdl-code-reviewer.md
│   │   ├── simulation-analyzer.md
│   │   ├── testbench-generator.md
│   │   └── fpga-performance-optimizer.md
│   └── settings.local.json           # Permissions & settings
│
├── vhdl-rl-iteration.skill           # Claude Code skill package (27KB)
│   # Contains: VHDL orchestration, testbench generation,
│   # log parsing, style guides, and error pattern references
│
├── PROJECT_STATUS.md                 # Overall project status
└── ORGANIZATION_SUMMARY.md           # Folder reorganization details
```

**Note:** Vivado project directories (`project/`) have been removed as they are regenerated from source files. The `sources/` directories are the single source of truth.

## Quick Navigation

### Learning Hub - Start Here! 📚
**All lessons from both projects are consolidated in the shared learnings directory:**
- **`shared/learnings/LEARNINGS_INDEX.md`** ⭐ - Comprehensive navigation guide with topic-based learning paths

### By Implementation

**Cholesky 3×3 Matrix Decomposition:**
- Start: `cholesky-implementation/README.md`
- Main Code: `cholesky-implementation/sources/code.vhd`
- Analysis: `cholesky-implementation/docs/CHOLESKY_PERFORMANCE_ANALYSIS.md`
- Bug Fix: `cholesky-implementation/docs/AGENT_INTEGRATION_GUIDE.md`

**Newton-Raphson Square Root:**
- Start: `newton-implementation/README.md`
- Main Code: `newton-implementation/sources/NewtonRaphson.vhd`
- Lessons: `newton-implementation/docs/newton_raphson_lessons.md`
- XSIM Guide: `newton-implementation/docs/xsim_debugging_techniques.md`

### By Topic (Lessons Database)

**Performance & Optimization:**
- `shared/learnings/CHOLESKY_PERFORMANCE_ANALYSIS.md` (latency/throughput analysis)
- `shared/learnings/newton_raphson_lessons.md` (algorithm optimization)
- `shared/documentation/PERFORMANCE_METRICS_SUMMARY.md` (quick reference)

**XSIM Debugging & Compatibility:**
- `shared/learnings/xsim_debugging_techniques.md` (binary search methodology)
- `shared/learnings/cholesky_xsim_solution.md` (XSIM workarounds)
- `shared/learnings/xsim_fixed_point_issue.md` (package function details)
- `shared/learnings/COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` (34KB master reference)

**Algorithm Implementation:**
- `shared/learnings/newton_raphson_lessons.md` (iterative algorithms)
- `shared/learnings/CHOLESKY_PERFORMANCE_ANALYSIS.md` (complex algorithms)

**Bug Fixing & Solutions:**
- `shared/learnings/AGENT_INTEGRATION_GUIDE.md` (Cholesky L33 bug fix example)
- `shared/learnings/cholesky_fixes_applied.md` (applied fixes summary)

**Tools & Automation:**
- `shared/tools/vhdl_claude_helper.py` (AI automation helper)
- `shared/tools/vhdl_iteration_orchestrator.py` (error categorization)

## Project Status Summary

### Cholesky 3×3 Decomposition
- **Compilation:** ✓ SUCCESS
- **Simulation:** ✓ SUCCESS (runs to completion)
- **Functional Status:** ⚠️ PARTIAL (5/6 matrix elements correct - 83%)
- **Critical Issue:** L33 signal overwriting bug (easy 5-10 min fix)
- **Latency:** 59.5 cycles @ 100 MHz
- **Optimization Potential:** 3-4× improvement possible

### Newton-Raphson Square Root
- **Compilation:** ✓ SUCCESS
- **Simulation:** ✓ SUCCESS
- **Functional Status:** ✓ VERIFIED (all tests pass)
- **Status:** Production ready
- **Convergence:** 12 iterations, quadratic convergence
- **Fixed-Point Format:** Q20.12 (precision ~3.8e-4)

## Key Metrics

| Metric | Value |
|--------|-------|
| **Cholesky Latency** | 59.5 cycles (595 ns @ 100 MHz) |
| **Cholesky Throughput** | 1.68 Mdecompositions/sec |
| **Newton-Raphson Throughput** | 5.0 Mops/sec |
| **Fixed-Point Format** | Q20.12 (20 int, 12 frac) |
| **Max Matrix Size** | 3×3 |

## Getting Started

### 1. Understand the Projects
```bash
# Read Cholesky overview
cat cholesky-implementation/README.md

# Read Newton-Raphson overview
cat newton-implementation/README.md
```

### 2. Review Source Code
```bash
# Cholesky main code
cat cholesky-implementation/sources/code.vhd

# Newton-Raphson implementation
cat newton-implementation/sources/NewtonRaphson.vhd
```

### 3. Create New Vivado Projects
```bash
# Create a new Vivado project from source files
cd <implementation-name>/sources/
vivado &  # Open Vivado GUI and create project from these sources

# Or use existing project structure if available
cd <implementation-name>/project/<project-name>/
vivado <project-name>.xpr
```

### 4. Review Analysis
```bash
# Performance analysis
cat cholesky-implementation/docs/CHOLESKY_PERFORMANCE_ANALYSIS.md

# VHDL best practices
cat shared/learnings/COMPREHENSIVE_VHDL_XSIM_REFERENCE.md
```

## Development Workflow

This section explains the systematic approach to VHDL development in this repository, emphasizing organization, iteration, and knowledge capture.

### Overview: Clean Source-Based Development

**Philosophy:** Keep VHDL source files separate from Vivado project files. The source files are the source of truth; Vivado projects are regenerated as needed.

**Key Principles:**
1. **Source files first** - All development happens in `sources/` directories
2. **Vivado projects are transient** - Can be recreated from sources at any time
3. **Knowledge is permanent** - Every iteration contributes to shared learnings
4. **Organize iterations cleanly** - Use structured iteration folders for experiments

### Step-by-Step Workflow

#### 1. Starting a New VHDL Implementation

```bash
# Create project structure
mkdir -p <algorithm-name>-implementation/{sources,docs,logs}

# Navigate to sources directory
cd <algorithm-name>-implementation/sources/
```

**What to create:**
- `sources/<module>.vhd` - Your VHDL implementation
- `sources/<module>_tb.vhd` - Corresponding testbench
- `docs/README.md` - Initial project documentation

**Example:**
```bash
mkdir -p matrix-multiply-implementation/{sources,docs,logs}
cd matrix-multiply-implementation/sources/
# Create matrix_multiply.vhd and matrix_multiply_tb.vhd
```

#### 2. Creating Vivado Projects (When Needed)

**Important:** Vivado projects are created from source files, not the other way around.

```bash
# Option A: Create project from Vivado GUI
cd <implementation-name>/sources/
vivado &
# File > Project > New > Add your .vhd files from sources/

# Option B: Use TCL script to create project
vivado -mode batch -source ../scripts/create_project.tcl
```

**Where to save Vivado projects:**
- If you create a Vivado project for synthesis/implementation, save it in `<implementation-name>/project/`
- **These can be deleted anytime** - they can be recreated from sources
- Not tracked in version control (add to .gitignore)

#### 3. Conducting Iterations Systematically

When experimenting with different design approaches or optimizations:

**Create iteration structure:**
```bash
mkdir -p <implementation-name>/vhdl_iterations/iteration_{0,1,2,3}
```

**Iteration workflow:**
```
iteration_0/  - Initial baseline implementation
iteration_1/  - First optimization attempt (e.g., pipeline stages)
iteration_2/  - Second approach (e.g., FSM-based control)
iteration_3/  - Final optimized version
```

**Example from CORDIC project:**
```
cordic-sin-implementation/
├── sources/
│   ├── cordic_sin_module.vhd          # Current stable version
│   └── cordic_sin_tb.vhd              # Main testbench
└── vhdl_iterations/
    ├── iteration_0/                   # Initial attempt: combinatorial
    │   ├── cordic_processor.vhd
    │   └── tb_cordic.vhd
    ├── iteration_1/                   # Second attempt: sequential FSM
    │   ├── cordic_control.vhd
    │   └── tb_cordic_fsm.vhd
    ├── iteration_2/                   # Third attempt: handshake protocol
    │   ├── cordic_control_v2.vhd
    │   ├── cordic_datapath.vhd
    │   └── tb_cordic_handshake.vhd
    └── iteration_3/                   # Final: pipelined version
        ├── cordic_pipeline.vhd
        └── tb_cordic_pipeline.vhd
```

**Iteration best practices:**
- Each iteration is self-contained (module + testbench)
- Document what changed between iterations in `docs/`
- Keep successful iterations for reference
- Promote best iteration to `sources/` when finalized

#### 4. Documenting and Sharing Learnings

**Critical workflow step:** Every project generates valuable knowledge. Capture it!

**Local documentation (in project folder):**
```bash
# Create detailed analysis in your project's docs/ folder
cd <implementation-name>/docs/

# Examples of documentation files:
echo "# Performance Analysis" > PERFORMANCE_ANALYSIS.md
echo "# Lessons Learned" > LESSONS_LEARNED.md
echo "# Bug Fixes Applied" > BUG_FIXES.md
echo "# XSIM Debugging Notes" > XSIM_DEBUGGING.md
```

**Share knowledge with other projects:**
```bash
# Copy important lessons to shared learnings
cp docs/PERFORMANCE_ANALYSIS.md ../shared/learnings/<project>_performance_analysis.md
cp docs/LESSONS_LEARNED.md ../shared/learnings/<project>_lessons.md

# Update the learnings index
nano ../shared/learnings/LEARNINGS_INDEX.md
# Add entries for your new files with brief descriptions
```

**What to document:**
- Performance metrics (latency, throughput, resource usage)
- Bug fixes and their solutions
- VHDL patterns that worked well
- Simulator-specific issues (XSIM quirks)
- Optimization insights
- Design decisions and trade-offs

#### 5. Using Claude Code Integration

This repository includes powerful AI assistance through Claude Code.

**vhdl-rl-iteration.skill:**
Located in the root directory, this skill provides:
- VHDL orchestration scripts
- Testbench generation utilities
- Vivado log parsing tools
- Style guides and error pattern references

**Custom slash commands** (in `.claude/commands/`):
```
/vhdl-master          - Comprehensive VHDL development assistance
/vhdl-orchestrator    - Orchestrate multi-iteration workflows
/vhdl-realistic       - Realistic VHDL design patterns
```

**Custom agents** (in `.claude/agents/`):
```
vhdl-code-reviewer         - Review code for syntax and design patterns
simulation-analyzer        - Analyze XSIM logs and debug failures
testbench-generator        - Generate comprehensive testbenches
fpga-performance-optimizer - Analyze timing and resource usage
```

**Example workflow with Claude Code:**
```bash
# 1. Ask Claude to review your VHDL code
# "Review my CORDIC implementation in sources/cordic_sin_module.vhd"

# 2. Generate a testbench
# "Generate a comprehensive testbench for matrix_multiply.vhd"

# 3. Debug simulation issues
# "Analyze the XSIM log in logs/simulation.log and identify the issue"

# 4. Optimize performance
# "Review the timing report and suggest optimizations for my design"
```

#### 6. Running Simulations and Tests

**Organized testing approach:**

```bash
# Run simulation and capture log
cd <implementation-name>/sources/
xvhdl <module>.vhd <module>_tb.vhd
xelab tb_<module> -debug typical
xsim tb_<module> -runall -log ../logs/simulation_$(date +%Y%m%d_%H%M%S).log
```

**Using automation scripts:**
```bash
# Use shared TCL scripts for standardized testing
vivado -mode batch -source ../../shared/scripts/run_simple_sim.tcl

# Use shell scripts for XSIM
../../shared/scripts/run_full_sim.sh
```

**Organize logs systematically:**
```
<implementation-name>/logs/
├── simulation_20251123_143022.log    # Timestamped simulation runs
├── synthesis_report_v1.log           # Synthesis attempts
├── timing_analysis.log               # Timing closure reports
└── iteration_comparison.txt          # Performance comparison across iterations
```

#### 7. Finalizing and Promoting Code

When an iteration is successful:

**1. Move to sources:**
```bash
# Copy best iteration to sources/
cp vhdl_iterations/iteration_3/cordic_pipeline.vhd sources/cordic_sin_module.vhd
cp vhdl_iterations/iteration_3/tb_cordic_pipeline.vhd sources/cordic_sin_tb.vhd
```

**2. Document the decision:**
```bash
# Update project README
echo "## Latest Version: Pipeline Implementation (from iteration_3)" >> README.md
echo "Chosen for 35% performance improvement over iteration_2" >> README.md
```

**3. Capture learnings:**
```bash
# Document what you learned
cd docs/
cat > ITERATION_SUMMARY.md << 'EOF'
# Iteration Summary

## Iterations Conducted
- iteration_0: Combinatorial (baseline)
- iteration_1: Sequential FSM (unsuccessful - timing issues)
- iteration_2: Handshake protocol (successful - 20% improvement)
- iteration_3: Pipeline (selected - 35% improvement)

## Key Learnings
- Pipelining critical for throughput
- Handshake protocol essential for variable latency
- FSM state encoding impacts resource usage

## Performance Comparison
| Iteration | Latency | Throughput | LUTs | FFs |
|-----------|---------|------------|------|-----|
| 0         | 10 cyc  | 100 Mops   | 450  | 200 |
| 2         | 8 cyc   | 120 Mops   | 520  | 280 |
| 3         | 6 cyc   | 135 Mops   | 580  | 340 |
EOF

# Share important findings
cp ITERATION_SUMMARY.md ../../shared/learnings/cordic_iteration_summary.md
```

### Workflow Summary Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Create Implementation Folder                             │
│    <algorithm>-implementation/{sources, docs, logs}         │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│ 2. Develop in sources/                                      │
│    - Write VHDL module                                      │
│    - Write testbench                                        │
│    - Create initial docs                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│ 3. Run Iterations (if needed)                               │
│    vhdl_iterations/iteration_N/                             │
│    - Test different approaches                              │
│    - Compare performance                                    │
│    - Document trade-offs                                    │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│ 4. Create Vivado Projects (optional)                        │
│    - For synthesis/implementation only                      │
│    - Save in project/ (can be deleted)                      │
│    - Regenerate from sources/ as needed                     │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│ 5. Document Learnings                                       │
│    - Local: docs/LESSONS.md                                 │
│    - Shared: shared/learnings/<project>_lessons.md          │
│    - Update: shared/learnings/LEARNINGS_INDEX.md            │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│ 6. Finalize                                                 │
│    - Move best iteration to sources/                        │
│    - Update README with status                              │
│    - Clean up temporary files                               │
│    - Keep learnings and iterations for reference            │
└─────────────────────────────────────────────────────────────┘
```

### Daily Development Practices

**Morning routine:**
1. Review `shared/learnings/LEARNINGS_INDEX.md` for relevant patterns
2. Check project status in `<implementation>/README.md`
3. Review yesterday's simulation logs in `logs/`

**During development:**
1. Make changes in `sources/` directory
2. Test immediately with XSIM or Vivado
3. Save logs with timestamps in `logs/`
4. Document interesting findings in `docs/`

**End of day:**
1. Update project README with progress
2. Commit source files (if using version control)
3. Copy any new learnings to `shared/learnings/`
4. Clean up temporary Vivado files (journals, logs)

**End of iteration:**
1. Document iteration results in `docs/`
2. Compare performance metrics
3. Update shared learnings if new patterns discovered
4. Clean up unsuccessful experiments (keep only reference iterations)

### File Organization Best Practices

**Always keep:**
- ✅ Source VHDL files (`sources/*.vhd`)
- ✅ Testbenches (`sources/*_tb.vhd`)
- ✅ Documentation (`docs/*.md`)
- ✅ Successful iterations (`vhdl_iterations/iteration_N/`)
- ✅ Shared learnings (`shared/learnings/*.md`)
- ✅ Automation scripts (`shared/scripts/*.{tcl,sh}`)
- ✅ Claude Code configuration (`.claude/`)

**Can be deleted:**
- ❌ Vivado project files (`.xpr`, `project/` directories)
- ❌ Simulation artifacts (`xsim.dir/`, `*.sim/`)
- ❌ Vivado logs and journals (`*.log`, `*.jou`)
- ❌ Cache directories (`.Xil/`, `*.cache/`)
- ❌ Unsuccessful iterations (after documenting why they failed)

**Regular cleanup routine:**
```bash
# Remove temporary Vivado files (safe - can regenerate)
find . -name "*.log" -delete
find . -name "*.jou" -delete
find . -name ".Xil" -type d -exec rm -rf {} +
find . -name "xsim.dir" -type d -exec rm -rf {} +
find . -name "*.cache" -type d -exec rm -rf {} +

# Keep only what matters: sources, docs, learnings, iterations
```

## Directory Organization Convention

### Project Folder Structure

For all new VHDL implementations, follow this pattern:

```
<algorithm-name>-implementation/
├── README.md                    # Project overview & status
├── sources/                     # VHDL source files
│   ├── *.vhd                   # Implementation files
│   └── *_tb.vhd                # Testbenches
├── project/                     # Vivado project (optional reference)
├── docs/                        # Project-specific documentation
│   ├── *.md                    # Implementation guides, analysis, lessons
│   └── [Files here are ALSO copied to shared/learnings/]
└── logs/                        # Simulation logs & reports
```

### Lessons Learned Convention ⭐

**Important:** All lessons and knowledge discovered during implementation must be documented and shared:

1. **Document in Project Folder**
   - Create detailed analysis/lesson documents in `<project>/docs/`
   - Example: CHOLESKY_PERFORMANCE_ANALYSIS.md, AGENT_INTEGRATION_GUIDE.md
   - These documents serve both as project reference and learning material

2. **Copy to Shared Learnings**
   - Copy important lessons to `shared/learnings/`
   - Use descriptive filenames that indicate the lesson topic
   - Preserve original formatting and content

3. **Update Learnings Index**
   - Update `shared/learnings/LEARNINGS_INDEX.md` with new materials
   - Add brief description of what the file covers
   - Create cross-references to related materials

**Rationale:**
- Project-specific docs stay in project folder for context
- Shared copies enable knowledge reuse across projects
- Centralized index makes knowledge discoverable
- Growing knowledge base compounds with each project

### Shared Resources Placement

**Shared resources** go in `shared/` directory:
- **Tools/Scripts:** `shared/tools/` or `shared/scripts/`
- **General Docs:** `shared/documentation/`
- **Knowledge Base:** `shared/learnings/` (lessons from all projects)
- **Prompts:** `shared/prompts/`

**Pattern for All Resources:**
```
shared/
├── learnings/                   # Lessons from all projects
│   ├── LEARNINGS_INDEX.md       # Master navigation guide
│   ├── <project>_*.md          # Files copied from projects
│   └── COMPREHENSIVE_VHDL_XSIM_REFERENCE.md
├── tools/
├── scripts/
├── prompts/
└── documentation/
```

## Custom Agents

Four custom agents are configured for task automation:

1. **vhdl-code-reviewer** - Review VHDL code for syntax and design patterns
2. **simulation-analyzer** - Analyze XSIM logs and test results
3. **testbench-generator** - Generate comprehensive testbenches
4. **performance-optimizer** - Analyze timing and resource usage

See `.claude/agents.json` for detailed specifications.

## Documentation Files

### 📚 Knowledge Base - Lessons Learned

**Start here to access all lessons and learnings:**
- **`shared/learnings/LEARNINGS_INDEX.md`** - Master index with topic-based navigation
- **`shared/learnings/`** - 9 files (128 KB) from both projects
  - All Cholesky project lessons copied here
  - All Newton-Raphson project lessons copied here
  - Complete VHDL reference guide

### Quick References
- `README.md` (this file) - Project navigation
- `shared/documentation/EXECUTIVE_SUMMARY.txt` - 15-minute overview
- `shared/documentation/PERFORMANCE_METRICS_SUMMARY.md` - Quick metrics
- `ORGANIZATION_SUMMARY.md` - Folder reorganization details

### Detailed Analysis
- `shared/learnings/CHOLESKY_PERFORMANCE_ANALYSIS.md` - 13 sections on latency/throughput
- `shared/learnings/COMPREHENSIVE_VHDL_XSIM_REFERENCE.md` - 34KB master VHDL reference

### Implementation Guides
- `shared/learnings/AGENT_INTEGRATION_GUIDE.md` - Cholesky L33 bug fix guide
- `shared/learnings/cholesky_xsim_solution.md` - XSIM compatibility solutions
- `shared/learnings/newton_raphson_lessons.md` - Algorithm implementation & optimization

## Tools & Scripts

### Python Tools
- `shared/tools/vhdl_claude_helper.py` - Pragmatic AI helper (350 LOC)
- `shared/tools/vhdl_iteration_orchestrator.py` - Iteration control (670 LOC)

### Testing Scripts
- TCL scripts for Vivado automation in `shared/scripts/`
- Shell scripts for XSIM testing in `shared/scripts/`
- Simulation logs and reports in `shared/scripts/logs/`

## Known Issues & Roadmap

### Immediate (Bug Fix)
- [ ] Fix Cholesky L33 signal overwriting (5-10 minutes)

### Short-term (Optimization)
- [ ] Add DSP-based division (1-2 weeks)
- [ ] Implement input FIFO for streaming (20% latency reduction)

### Medium-term (Enhancement)
- [ ] Parallel sqrt computation (35-50% improvement)
- [ ] Support variable matrix sizes

### Long-term (Generalization)
- [ ] Streaming interface support
- [ ] AXI wrapper for integration
- [ ] Library of hardware algorithms

## Technology Stack

- **HDL:** VHDL (IEEE 1076-2002)
- **Tools:** Vivado 2023.02 - 2025.1, XSIM simulator
- **Fixed-Point:** Q20.12 format (32-bit signed)
- **Automation:** Python, Bash, Vivado TCL
- **AI Assistance:** Claude Code with custom prompts

## References

- Cholesky Decomposition: Matrix analysis and numerical linear algebra
- Newton-Raphson: Numerical methods for function root finding
- Fixed-Point Arithmetic: Embedded systems guide
- VHDL Best Practices: See `shared/learnings/`

## Project Statistics

- **Total VHDL LOC:** ~508 lines
- **Documentation:** 6 comprehensive analysis files
- **Knowledge Base:** 9 files in shared/learnings/ (128 KB total)
  - Cholesky project lessons: 4 files
  - Newton-Raphson project lessons: 3 files
  - General VHDL reference: 1 file
  - Learnings index & navigation: 1 file
- **Tools:** 2 Python automation scripts (1020+ LOC)
- **Test Scripts:** 10+ TCL/shell scripts
- **Simulation Logs:** 12+ comprehensive logs
- **Navigation Guides:** 3 main README files (cholesky, newton, root)

## Adding New VHDL Implementations

Follow this workflow when implementing new algorithms:

### 1. Create Project Folder
```bash
mkdir <algorithm-name>-implementation/{sources,docs,project,logs}
```

### 2. Implement & Document
- Place VHDL files in `sources/`
- Create comprehensive analysis in `docs/`
- Document lessons learned: bug fixes, optimization insights, VHDL patterns
- Store Vivado project in `project/`
- Keep simulation logs in `logs/`

### 3. Share Knowledge (Critical Step)
- Copy important lessons to `shared/learnings/`
- Update `shared/learnings/LEARNINGS_INDEX.md` with:
  - New file descriptions
  - Topic mappings
  - Cross-references to related materials
- Create/update project README with status and metrics

### 4. Maintain Knowledge Base
The knowledge base grows with each project. New projects benefit from existing lessons while contributing their own.

## Support & Feedback

For issues, questions, or contributions:
1. **Start with learnings:** Check `shared/learnings/LEARNINGS_INDEX.md`
2. **Topic-specific help:** Browse lessons by category
3. **Project context:** Check relevant README.md in project folder
4. **Technical reference:** Consult `shared/learnings/COMPREHENSIVE_VHDL_XSIM_REFERENCE.md`
5. **Tools & automation:** Check `.claude/` for commands and agents

## Future Projects

New VHDL implementations should follow the established conventions:
- ✓ Separate folder for each algorithm/implementation
- ✓ Self-contained with sources, docs, project, logs
- ✓ Project-specific README with overview & status
- ✓ Lessons documented in project/docs/ AND copied to shared/learnings/
- ✓ Growing knowledge base from accumulated experience

---

**Last Updated:** November 2025
**Project Status:** Actively Developed
**Organization Level:** Fully Structured
**Knowledge Base:** 128 KB across 9 files
**Convention:** Lessons Learned Always Shared

## Structure & Convention Overview

This project demonstrates a systematic approach to VHDL development:
1. **Modular Implementation** - Each algorithm in separate folder
2. **Shared Knowledge** - Lessons learned centralized and indexed
3. **Scalable Documentation** - Growing knowledge base from all projects
4. **Future-Proof** - Clear conventions for new implementations

The structure balances project autonomy (isolated folders) with knowledge sharing (centralized learnings), creating a sustainable system for growing VHDL expertise.
