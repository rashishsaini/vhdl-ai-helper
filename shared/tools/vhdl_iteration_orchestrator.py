#!/usr/bin/env python3
"""
VHDL Iteration Orchestrator for Claude Code
===========================================
This script intelligently categorizes Vivado errors and uses Claude Code
appropriately for different error types. It maintains realistic expectations
about what can be automated versus what requires human intervention.

Author: ML-VHDL Integration Framework
Version: 1.0
"""

import os
import re
import json
import shutil
import subprocess
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Tuple, Optional
from enum import Enum

class ErrorCategory(Enum):
    """Categories of errors based on automation feasibility"""
    SYNTAX = "syntax"              # Fully automatable
    PORT_MISMATCH = "port"          # Highly automatable  
    MISSING_SIGNAL = "signal"       # Highly automatable
    TYPE_MISMATCH = "type"          # Moderately automatable
    TIMING = "timing"               # Requires human insight
    RESOURCE = "resource"           # Requires architectural changes
    FUNCTIONAL = "functional"       # Requires algorithm understanding
    UNKNOWN = "unknown"             # Needs investigation

class VHDLIterationOrchestrator:
    """
    Orchestrates iterative VHDL development using Claude Code
    for appropriate error categories while maintaining context
    and iteration history.
    """
    
    def __init__(self, project_dir: str, iteration_dir: str, max_iterations: int = 5):
        """
        Initialize the orchestrator with project paths and limits.
        
        The max_iterations limit prevents infinite loops when facing
        errors that Claude Code cannot resolve.
        """
        self.project_dir = Path(project_dir)
        self.iteration_dir = Path(iteration_dir)
        self.max_iterations = max_iterations
        self.current_iteration = 0
        self.iteration_history = []
        
        # Create iteration directory structure
        self.iteration_dir.mkdir(parents=True, exist_ok=True)
        
        # Error pattern definitions - these are based on real Vivado output patterns
        self.error_patterns = {
            ErrorCategory.SYNTAX: [
                r"Syntax error near",
                r"expecting \w+, found",
                r"illegal \w+ declaration",
                r"parse error"
            ],
            ErrorCategory.PORT_MISMATCH: [
                r"Port .* has \d+ bits",
                r"Width mismatch",
                r"Port size mismatch",
                r"Formal port .* has no actual"
            ],
            ErrorCategory.MISSING_SIGNAL: [
                r"Signal .* is not declared",
                r"Unknown identifier",
                r"Object .* not found",
                r"Undefined signal"
            ],
            ErrorCategory.TYPE_MISMATCH: [
                r"Type mismatch",
                r"Cannot convert type",
                r"Incompatible types",
                r"Type error in assignment"
            ],
            ErrorCategory.TIMING: [
                r"Timing constraint not met",
                r"Setup violation",
                r"Hold violation",
                r"Clock skew exceeded"
            ],
            ErrorCategory.RESOURCE: [
                r"exceeded .* resources",
                r"Insufficient .* blocks",
                r"Resource utilization exceeded",
                r"Cannot fit design"
            ],
            ErrorCategory.FUNCTIONAL: [
                r"Simulation mismatch",
                r"Assertion failed",
                r"Test failed:",
                r"Expected .* but got"
            ]
        }
        
    def categorize_error(self, error_text: str) -> Tuple[ErrorCategory, float]:
        """
        Categorize an error and return confidence level.
        
        This is crucial - we only want to attempt automated fixes
        for errors we understand well and can handle reliably.
        """
        error_lower = error_text.lower()
        
        for category, patterns in self.error_patterns.items():
            for pattern in patterns:
                if re.search(pattern, error_text, re.IGNORECASE):
                    # High confidence for syntax and structural errors
                    if category in [ErrorCategory.SYNTAX, ErrorCategory.PORT_MISMATCH, 
                                    ErrorCategory.MISSING_SIGNAL]:
                        confidence = 0.9
                    # Medium confidence for type issues
                    elif category == ErrorCategory.TYPE_MISMATCH:
                        confidence = 0.7
                    # Low confidence for timing and resource issues
                    else:
                        confidence = 0.3
                    return category, confidence
        
        return ErrorCategory.UNKNOWN, 0.0
    
    def parse_vivado_log(self, log_file: Path) -> List[Dict]:
        """
        Parse Vivado output to extract errors and warnings.
        
        This parser understands Vivado's multi-line error format
        and preserves context for better Claude Code understanding.
        """
        errors = []
        current_error = None
        context_lines = []
        
        with open(log_file, 'r') as f:
            lines = f.readlines()
            
        for i, line in enumerate(lines):
            # Vivado error format: ERROR: [<tag>] message
            if 'ERROR:' in line or 'CRITICAL WARNING:' in line:
                # Save previous error if exists
                if current_error:
                    errors.append(current_error)
                
                # Extract file location if present
                file_match = re.search(r'"([^"]+\.vhd[l]?)".*line (\d+)', line)
                
                # Get surrounding context (5 lines before and after)
                context_start = max(0, i - 5)
                context_end = min(len(lines), i + 6)
                context = ''.join(lines[context_start:context_end])
                
                current_error = {
                    'text': line.strip(),
                    'file': file_match.group(1) if file_match else None,
                    'line': int(file_match.group(2)) if file_match else None,
                    'context': context,
                    'category': None,
                    'confidence': 0.0
                }
                
                # Categorize the error
                category, confidence = self.categorize_error(line)
                current_error['category'] = category
                current_error['confidence'] = confidence
        
        # Don't forget the last error
        if current_error:
            errors.append(current_error)
            
        return errors
    
    def generate_claude_prompt(self, errors: List[Dict], vhdl_file: Path, 
                              testbench_file: Optional[Path] = None) -> str:
        """
        Generate an intelligent prompt for Claude Code based on error types.
        
        The prompt strategy changes based on what we're dealing with:
        - Syntax errors: Direct fix request
        - Structural errors: Contextual fix with interface preservation  
        - Complex errors: Analysis and suggestion request
        """
        # Read the current VHDL code
        with open(vhdl_file, 'r') as f:
            vhdl_content = f.read()
        
        tb_content = ""
        if testbench_file and testbench_file.exists():
            with open(testbench_file, 'r') as f:
                tb_content = f.read()
        
        # Group errors by category for better organization
        errors_by_category = {}
        for error in errors:
            cat = error['category']
            if cat not in errors_by_category:
                errors_by_category[cat] = []
            errors_by_category[cat].append(error)
        
        # Build the prompt strategically
        prompt = f"""Analyze and fix the following VHDL code based on Vivado synthesis/simulation errors.

## Current VHDL Code:
```vhdl
{vhdl_content}
```

"""
        
        if tb_content:
            prompt += f"""## Current Testbench:
```vhdl
{tb_content}
```

"""
        
        prompt += "## Vivado Errors to Fix:\n\n"
        
        # Handle different error categories with appropriate instructions
        for category, category_errors in errors_by_category.items():
            if category in [ErrorCategory.SYNTAX, ErrorCategory.PORT_MISMATCH, 
                          ErrorCategory.MISSING_SIGNAL]:
                prompt += f"### {category.value.capitalize()} Errors (Please fix directly):\n"
                for err in category_errors:
                    prompt += f"- {err['text']}\n"
                    if err['file'] and err['line']:
                        prompt += f"  Location: {err['file']}:{err['line']}\n"
            
            elif category == ErrorCategory.TYPE_MISMATCH:
                prompt += f"### Type Mismatch Errors (Fix with minimal changes):\n"
                for err in category_errors:
                    prompt += f"- {err['text']}\n"
                prompt += "Note: Preserve the intended functionality while fixing type issues.\n"
            
            elif category in [ErrorCategory.TIMING, ErrorCategory.RESOURCE]:
                prompt += f"### {category.value.capitalize()} Issues (Provide analysis and suggestions):\n"
                for err in category_errors:
                    prompt += f"- {err['text']}\n"
                prompt += """For these issues, provide:
1. Root cause analysis
2. Suggested fixes with trade-offs
3. Code modifications if straightforward
4. Architectural recommendations if needed
"""
            
        prompt += """
## Instructions:
1. Fix all syntax and structural errors directly in the code
2. Preserve all existing interfaces unless changes are necessary
3. Add comments explaining significant changes
4. For timing/resource issues, provide detailed analysis even if you cannot fully fix them
5. Ensure the testbench remains compatible with any interface changes
6. Generate separate, clearly marked code blocks for the fixed VHDL and testbench

## Output Format:
Provide the corrected VHDL code in a code block marked with ```vhdl, 
followed by the updated testbench (if needed) in another code block.
Include a summary of changes and any recommendations for issues that require human intervention.
"""
        
        return prompt
    
    def save_iteration(self, iteration_num: int, vhdl_content: str, 
                      tb_content: str, errors: List[Dict], fixed: bool):
        """
        Save each iteration with full context for learning and debugging.
        
        This iteration history is invaluable for:
        1. Understanding what Claude Code can and cannot fix
        2. Detecting oscillating fixes (fixing A breaks B, fixing B breaks A)
        3. Building a knowledge base for your specific design patterns
        """
        iteration_path = self.iteration_dir / f"iteration_{iteration_num:03d}"
        iteration_path.mkdir(exist_ok=True)
        
        # Save VHDL and testbench
        with open(iteration_path / "design.vhd", 'w') as f:
            f.write(vhdl_content)
        
        with open(iteration_path / "testbench.vhd", 'w') as f:
            f.write(tb_content)
        
        # Save error analysis
        error_analysis = {
            'iteration': iteration_num,
            'timestamp': datetime.now().isoformat(),
            'fixed': fixed,
            'total_errors': len(errors),
            'errors_by_category': {}
        }
        
        for error in errors:
            cat = error['category'].value
            if cat not in error_analysis['errors_by_category']:
                error_analysis['errors_by_category'][cat] = []
            error_analysis['errors_by_category'][cat].append({
                'text': error['text'],
                'confidence': error['confidence']
            })
        
        with open(iteration_path / "analysis.json", 'w') as f:
            json.dump(error_analysis, f, indent=2)
        
        self.iteration_history.append(error_analysis)
    
    def detect_oscillation(self) -> bool:
        """
        Detect if we're stuck in a fix-break-fix cycle.
        
        This is a critical safety mechanism. Hardware errors often have
        complex dependencies where fixing one issue breaks another.
        """
        if len(self.iteration_history) < 3:
            return False
        
        # Check if error patterns repeat every 2-3 iterations
        recent = self.iteration_history[-3:]
        error_signatures = [
            tuple(sorted(h['errors_by_category'].keys())) 
            for h in recent
        ]
        
        # If we see the same error pattern multiple times, we're oscillating
        return len(set(error_signatures)) < len(error_signatures)
    
    def should_attempt_autofix(self, errors: List[Dict]) -> bool:
        """
        Decide whether automated fixing is appropriate.
        
        This decision function embodies the wisdom of knowing when
        NOT to use automation - which is just as important as knowing
        when to use it.
        """
        if not errors:
            return False
        
        # Calculate average confidence across all errors
        avg_confidence = sum(e['confidence'] for e in errors) / len(errors)
        
        # Count high-confidence fixable errors
        fixable_errors = sum(1 for e in errors 
                           if e['category'] in [ErrorCategory.SYNTAX, 
                                               ErrorCategory.PORT_MISMATCH,
                                               ErrorCategory.MISSING_SIGNAL]
                           and e['confidence'] > 0.8)
        
        # Decision logic
        if avg_confidence > 0.7 and fixable_errors > 0:
            return True
        elif all(e['category'] == ErrorCategory.TIMING for e in errors):
            # Pure timing issues need human insight
            return False
        elif self.detect_oscillation():
            # Stop if we're in a loop
            print("WARNING: Oscillation detected. Manual intervention required.")
            return False
        else:
            # When in doubt, attempt with low expectations
            return avg_confidence > 0.5
    
    def run_vivado(self, vhdl_file: Path, testbench_file: Path) -> Tuple[bool, Path]:
        """
        Run Vivado synthesis and simulation, return success status and log file.
        
        This is a simplified version - in reality, you'd have separate
        synthesis and simulation runs with different error handling.
        """
        # Create TCL script for Vivado batch mode
        tcl_script = self.iteration_dir / "run_vivado.tcl"
        with open(tcl_script, 'w') as f:
            f.write(f"""
# Vivado batch mode script
create_project -force test_project ./vivado_project -part xc7a100tcsg324-1
add_files {vhdl_file}
add_files -fileset sim_1 {testbench_file}
set_property top [file rootname [file tail {vhdl_file}]] [current_fileset]
update_compile_order -fileset sources_1

# Run synthesis
synth_design -top [file rootname [file tail {vhdl_file}]]

# Run simulation
set_property top [file rootname [file tail {testbench_file}]] [get_filesets sim_1]
launch_simulation
run all
exit
""")
        
        # Run Vivado in batch mode
        log_file = self.iteration_dir / f"vivado_run_{self.current_iteration}.log"
        try:
            result = subprocess.run(
                ['vivado', '-mode', 'batch', '-source', str(tcl_script)],
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout
            )
            
            with open(log_file, 'w') as f:
                f.write(result.stdout)
                f.write(result.stderr)
            
            # Check for success (no ERROR: messages)
            success = 'ERROR:' not in result.stdout and result.returncode == 0
            
            return success, log_file
            
        except subprocess.TimeoutExpired:
            print("ERROR: Vivado execution timed out")
            return False, log_file
        except Exception as e:
            print(f"ERROR: Failed to run Vivado: {e}")
            return False, log_file
    
    def extract_code_from_claude_response(self, response: str) -> Tuple[str, str]:
        """
        Extract VHDL and testbench code from Claude's response.
        
        Claude Code outputs are generally well-structured, but we need
        to handle various response formats robustly.
        """
        vhdl_pattern = r'```vhdl\n(.*?)```'
        
        matches = re.findall(vhdl_pattern, response, re.DOTALL)
        
        if len(matches) >= 2:
            # Assume first is design, second is testbench
            return matches[0], matches[1]
        elif len(matches) == 1:
            # Only design was updated
            return matches[0], ""
        else:
            # No code blocks found - might be analysis only
            return "", ""
    
    def run_iteration(self, vhdl_file: Path, testbench_file: Path) -> bool:
        """
        Run a single iteration of the error-fix cycle.
        
        Returns True if successful (no errors) or if we should stop trying.
        """
        print(f"\n=== Iteration {self.current_iteration + 1} ===")
        
        # Run Vivado
        success, log_file = self.run_vivado(vhdl_file, testbench_file)
        
        if success:
            print("SUCCESS: Design synthesized and simulated without errors!")
            return True
        
        # Parse errors from log
        errors = self.parse_vivado_log(log_file)
        print(f"Found {len(errors)} errors")
        
        # Analyze error distribution
        error_categories = {}
        for error in errors:
            cat = error['category'].value
            error_categories[cat] = error_categories.get(cat, 0) + 1
        
        print("Error distribution:")
        for cat, count in error_categories.items():
            print(f"  {cat}: {count}")
        
        # Decide whether to attempt automated fix
        if not self.should_attempt_autofix(errors):
            print("\nINFO: Errors require manual intervention.")
            print("Automated fixing not recommended for:")
            for cat in [ErrorCategory.TIMING, ErrorCategory.RESOURCE, ErrorCategory.FUNCTIONAL]:
                if cat.value in error_categories:
                    print(f"  - {cat.value} errors")
            return True  # Stop iteration but not due to success
        
        # Generate prompt for Claude Code
        prompt = self.generate_claude_prompt(errors, vhdl_file, testbench_file)
        
        # Save prompt for debugging
        prompt_file = self.iteration_dir / f"prompt_{self.current_iteration}.md"
        with open(prompt_file, 'w') as f:
            f.write(prompt)
        
        print(f"Calling Claude Code to fix {sum(1 for e in errors if e['confidence'] > 0.7)} high-confidence errors...")
        
        # Call Claude Code (this would be the actual subprocess call)
        # For now, this is a placeholder - you'd implement the actual call
        response = self.call_claude_code(prompt_file)
        
        # Extract fixed code from response
        fixed_vhdl, fixed_tb = self.extract_code_from_claude_response(response)
        
        if not fixed_vhdl:
            print("WARNING: No fixed code generated. Manual intervention required.")
            return True
        
        # Save the iteration
        with open(vhdl_file, 'r') as f:
            current_vhdl = f.read()
        with open(testbench_file, 'r') as f:
            current_tb = f.read()
        
        self.save_iteration(
            self.current_iteration,
            current_vhdl,
            current_tb,
            errors,
            False
        )
        
        # Update files with fixed versions
        with open(vhdl_file, 'w') as f:
            f.write(fixed_vhdl)
        
        if fixed_tb:
            with open(testbench_file, 'w') as f:
                f.write(fixed_tb)
        
        self.current_iteration += 1
        
        # Check iteration limit
        if self.current_iteration >= self.max_iterations:
            print(f"\nWARNING: Reached maximum iterations ({self.max_iterations})")
            print("Manual intervention required to resolve remaining issues.")
            return True
        
        return False
    
    def call_claude_code(self, prompt_file: Path) -> str:
        """
        Call Claude Code with the generated prompt.
        
        This is where you'd integrate with the actual Claude Code CLI.
        The implementation depends on your specific setup.
        """
        try:
            # Example command - adjust based on your Claude Code installation
            result = subprocess.run(
                ['claude-code', 'run', str(prompt_file)],
                capture_output=True,
                text=True,
                timeout=60
            )
            
            return result.stdout
            
        except subprocess.TimeoutExpired:
            print("ERROR: Claude Code call timed out")
            return ""
        except Exception as e:
            print(f"ERROR: Failed to call Claude Code: {e}")
            return ""
    
    def generate_report(self):
        """
        Generate a final report summarizing what was fixed and what wasn't.
        
        This report is crucial for understanding the limits of automation
        and planning manual intervention strategies.
        """
        report_path = self.iteration_dir / "iteration_report.md"
        
        with open(report_path, 'w') as f:
            f.write("# VHDL Iteration Report\n\n")
            f.write(f"Total iterations: {self.current_iteration}\n")
            f.write(f"Generated: {datetime.now().isoformat()}\n\n")
            
            f.write("## Iteration Summary\n\n")
            
            for i, iteration in enumerate(self.iteration_history):
                f.write(f"### Iteration {i+1}\n")
                f.write(f"- Timestamp: {iteration['timestamp']}\n")
                f.write(f"- Total errors: {iteration['total_errors']}\n")
                f.write("- Error categories:\n")
                for cat, errors in iteration['errors_by_category'].items():
                    f.write(f"  - {cat}: {len(errors)} errors\n")
                f.write("\n")
            
            # Analyze trends
            f.write("## Automation Effectiveness\n\n")
            
            # Categories that were successfully fixed
            fixed_categories = set()
            unfixed_categories = set()
            
            if len(self.iteration_history) > 1:
                first_errors = set(self.iteration_history[0]['errors_by_category'].keys())
                last_errors = set(self.iteration_history[-1]['errors_by_category'].keys())
                
                fixed_categories = first_errors - last_errors
                unfixed_categories = last_errors
                
                f.write("### Successfully Fixed Categories:\n")
                for cat in fixed_categories:
                    f.write(f"- {cat}\n")
                
                f.write("\n### Remaining Issues (Require Manual Intervention):\n")
                for cat in unfixed_categories:
                    f.write(f"- {cat}\n")
            
            f.write("\n## Recommendations\n\n")
            
            if ErrorCategory.TIMING.value in unfixed_categories:
                f.write("- **Timing Issues**: Consider pipeline optimization, ")
                f.write("clock domain crossing analysis, or architectural changes.\n")
            
            if ErrorCategory.RESOURCE.value in unfixed_categories:
                f.write("- **Resource Issues**: Review resource sharing opportunities, ")
                f.write("consider time-multiplexing, or target a larger device.\n")
            
            if ErrorCategory.FUNCTIONAL.value in unfixed_categories:
                f.write("- **Functional Issues**: Review algorithm implementation, ")
                f.write("check for race conditions, and verify state machine logic.\n")
            
            if self.detect_oscillation():
                f.write("- **Oscillation Detected**: The fixes are creating circular ")
                f.write("dependencies. Manual architectural review required.\n")
        
        print(f"\nReport generated: {report_path}")

def main():
    """
    Example usage of the VHDL Iteration Orchestrator.
    
    This demonstrates a realistic workflow that acknowledges both
    the power and limitations of automated VHDL iteration.
    """
    import argparse
    
    parser = argparse.ArgumentParser(description='VHDL Iteration Orchestrator using Claude Code')
    parser.add_argument('vhdl_file', help='Path to main VHDL file')
    parser.add_argument('testbench', help='Path to testbench file')
    parser.add_argument('--iterations', type=int, default=5, help='Maximum iterations')
    parser.add_argument('--output-dir', default='./iterations', help='Directory for iteration history')
    
    args = parser.parse_args()
    
    # Initialize orchestrator
    orchestrator = VHDLIterationOrchestrator(
        project_dir=os.path.dirname(args.vhdl_file),
        iteration_dir=args.output_dir,
        max_iterations=args.iterations
    )
    
    # Run iteration loop
    vhdl_path = Path(args.vhdl_file)
    tb_path = Path(args.testbench)
    
    print("Starting VHDL iteration process...")
    print(f"Design: {vhdl_path}")
    print(f"Testbench: {tb_path}")
    print(f"Max iterations: {args.iterations}\n")
    
    while orchestrator.current_iteration < orchestrator.max_iterations:
        if orchestrator.run_iteration(vhdl_path, tb_path):
            break
    
    # Generate final report
    orchestrator.generate_report()
    
    print("\n" + "="*50)
    print("VHDL Iteration Process Complete")
    print(f"Check {args.output_dir} for iteration history and report")

if __name__ == "__main__":
    main()
