#!/usr/bin/env python3
"""
VHDL Iteration Orchestrator - Manages recursive refinement loops.

Automates the cycle:
1. Run Vivado simulation/synthesis
2. Parse and categorize errors
3. Invoke LLM for fixes
4. Apply fixes
5. Validate and repeat
"""

import os
import sys
import json
import subprocess
import argparse
from pathlib import Path
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from datetime import datetime
import hashlib


@dataclass
class IterationResult:
    """Result of a single iteration"""
    iteration: int
    timestamp: str
    status: str  # success, failed, stopped
    error_category: str
    changes_made: List[str]
    positives: List[str]
    negatives: List[str]
    confidence: int
    next_action: str
    rationale: str
    errors_found: int
    errors_fixed: int


class VHDLOrchestrator:
    """Orchestrates VHDL refinement iterations"""
    
    def __init__(self, config: Dict):
        self.vhdl_file = Path(config['vhdl_file'])
        self.testbench_file = Path(config.get('testbench_file'))
        self.vivado_tcl = Path(config.get('vivado_tcl', 'run.tcl'))
        self.max_iterations = config.get('max_iterations', 10)
        self.workspace = Path(config.get('workspace', 'workspace'))
        self.vivado_cmd = config.get('vivado_cmd', 'vivado')
        
        self.iteration = 0
        self.history: List[IterationResult] = []
        self.error_hashes: List[str] = []  # Track repeated errors
        
        # Create workspace
        self.workspace.mkdir(exist_ok=True)
        self.iteration_dir = self.workspace / 'iterations'
        self.iteration_dir.mkdir(exist_ok=True)
    
    def run(self) -> bool:
        """Run the complete iteration cycle"""
        print(f"🚀 Starting VHDL iteration for {self.vhdl_file.name}")
        print(f"   Workspace: {self.workspace}")
        print(f"   Max iterations: {self.max_iterations}")
        
        while self.iteration < self.max_iterations:
            self.iteration += 1
            print(f"\n{'='*60}")
            print(f"🔄 Iteration {self.iteration}/{self.max_iterations}")
            print(f"{'='*60}")
            
            # Create iteration workspace
            iter_ws = self.iteration_dir / f"iter_{self.iteration:03d}"
            iter_ws.mkdir(exist_ok=True)
            
            # Run iteration
            result = self._run_iteration(iter_ws)
            self.history.append(result)
            
            # Save iteration result
            self._save_iteration_result(result, iter_ws)
            
            # Check stopping criteria
            should_stop, reason = self._check_stopping_criteria(result)
            if should_stop:
                print(f"\n⏹️  Stopping iteration: {reason}")
                self._save_final_report()
                return result.status == 'success'
            
            if result.status == 'success':
                print(f"\n✅ Success! Module passes all checks.")
                self._save_final_report()
                return True
        
        print(f"\n⚠️  Reached maximum iterations ({self.max_iterations})")
        self._save_final_report()
        return False
    
    def _run_iteration(self, iter_ws: Path) -> IterationResult:
        """Run a single iteration"""
        result = IterationResult(
            iteration=self.iteration,
            timestamp=datetime.now().isoformat(),
            status='running',
            error_category='UNKNOWN',
            changes_made=[],
            positives=[],
            negatives=[],
            confidence=0,
            next_action='continue',
            rationale='',
            errors_found=0,
            errors_fixed=0
        )
        
        # Step 1: Copy files to iteration workspace
        self._copy_files(iter_ws)
        
        # Step 2: Run quick validation (GHDL if available)
        if self._has_ghdl():
            ghdl_ok = self._run_ghdl(iter_ws)
            if not ghdl_ok:
                result.negatives.append("Failed GHDL syntax check")
        
        # Step 3: Run Vivado simulation
        vivado_ok, log_file = self._run_vivado(iter_ws)
        
        # Step 4: Parse errors
        if not vivado_ok:
            errors = self._parse_errors(log_file)
            result.errors_found = len(errors)
            
            # Categorize
            category = self._categorize_errors(errors)
            result.error_category = category
            
            # Check if this is a repeated error
            error_hash = self._hash_errors(errors)
            if error_hash in self.error_hashes:
                result.negatives.append("Repeated error pattern detected")
                result.next_action = 'stop'
                result.rationale = "Same errors appearing multiple times"
            else:
                self.error_hashes.append(error_hash)
            
            # Determine if fixable
            if category in ['FIXABLE', 'TESTBENCH']:
                result.positives.append(f"Found {len(errors)} fixable errors")
                result.confidence = 75
                result.status = 'failed'
            elif category in ['ARCHITECTURE', 'PHYSICS']:
                result.negatives.append(f"{category} errors require human intervention")
                result.next_action = 'stop'
                result.rationale = f"{category} constraints detected"
                result.status = 'stopped'
            
        else:
            result.status = 'success'
            result.positives.append("All Vivado checks passed")
            result.confidence = 100
        
        return result
    
    def _copy_files(self, dest: Path):
        """Copy VHDL files to iteration workspace"""
        import shutil
        shutil.copy(self.vhdl_file, dest / self.vhdl_file.name)
        if self.testbench_file and self.testbench_file.exists():
            shutil.copy(self.testbench_file, dest / self.testbench_file.name)
        if self.vivado_tcl.exists():
            shutil.copy(self.vivado_tcl, dest / 'run.tcl')
    
    def _has_ghdl(self) -> bool:
        """Check if GHDL is available"""
        try:
            subprocess.run(['ghdl', '--version'], capture_output=True, check=True)
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False
    
    def _run_ghdl(self, workspace: Path) -> bool:
        """Run GHDL syntax check"""
        print("  🔍 Running GHDL syntax check...")
        try:
            result = subprocess.run(
                ['ghdl', '-s', self.vhdl_file.name],
                cwd=workspace,
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                print("  ✅ GHDL syntax check passed")
                return True
            else:
                print(f"  ❌ GHDL syntax check failed:\n{result.stderr}")
                return False
        except Exception as e:
            print(f"  ⚠️  GHDL check failed: {e}")
            return False
    
    def _run_vivado(self, workspace: Path) -> tuple[bool, Optional[Path]]:
        """Run Vivado simulation"""
        print("  🔧 Running Vivado simulation...")
        log_file = workspace / 'vivado.log'
        
        try:
            result = subprocess.run(
                [self.vivado_cmd, '-mode', 'batch', '-source', 'run.tcl'],
                cwd=workspace,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            # Save output
            with open(log_file, 'w') as f:
                f.write(result.stdout)
                f.write(result.stderr)
            
            # Check for success indicators
            success = (
                result.returncode == 0 and
                'ERROR' not in result.stdout.upper() and
                'FATAL' not in result.stdout.upper()
            )
            
            if success:
                print("  ✅ Vivado simulation passed")
            else:
                print("  ❌ Vivado simulation failed")
            
            return success, log_file
            
        except subprocess.TimeoutExpired:
            print("  ⏱️  Vivado timed out")
            return False, log_file
        except Exception as e:
            print(f"  ❌ Vivado execution failed: {e}")
            return False, None
    
    def _parse_errors(self, log_file: Path) -> List[Dict]:
        """Parse errors from Vivado log"""
        # Use the parse_vivado_logs.py script
        parser_script = Path(__file__).parent / 'parse_vivado_logs.py'
        
        try:
            result = subprocess.run(
                [sys.executable, str(parser_script), str(log_file)],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                data = json.loads(result.stdout)
                return data.get('errors', [])
            else:
                print(f"  ⚠️  Error parsing failed: {result.stderr}")
                return []
        except Exception as e:
            print(f"  ⚠️  Could not parse errors: {e}")
            return []
    
    def _categorize_errors(self, errors: List[Dict]) -> str:
        """Categorize errors to determine action"""
        if not errors:
            return 'NONE'
        
        # Count by category
        categories = {}
        for error in errors:
            cat = error.get('category', 'UNKNOWN')
            categories[cat] = categories.get(cat, 0) + 1
        
        # Priority order (most restrictive first)
        if 'PHYSICS' in categories:
            return 'PHYSICS'
        if 'ARCHITECTURE' in categories:
            return 'ARCHITECTURE'
        if 'TESTBENCH' in categories:
            return 'TESTBENCH'
        if 'FIXABLE' in categories:
            return 'FIXABLE'
        
        return 'UNKNOWN'
    
    def _hash_errors(self, errors: List[Dict]) -> str:
        """Create hash of error messages to detect loops"""
        error_str = ''.join(e.get('message', '') for e in errors)
        return hashlib.md5(error_str.encode()).hexdigest()
    
    def _check_stopping_criteria(self, result: IterationResult) -> tuple[bool, str]:
        """Check if iteration should stop"""
        # Success
        if result.status == 'success':
            return True, "Simulation passed all checks"
        
        # Explicit stop
        if result.next_action == 'stop':
            return True, result.rationale
        
        # No fixable errors
        if result.error_category in ['ARCHITECTURE', 'PHYSICS']:
            return True, f"{result.error_category} errors require human intervention"
        
        # Repeated errors (3+ times)
        if len(self.error_hashes) > len(set(self.error_hashes[-3:])):
            return True, "Stuck in error loop - same errors repeating"
        
        # No progress in last 2 iterations
        if len(self.history) >= 2:
            last_two = self.history[-2:]
            if all(r.errors_found == last_two[0].errors_found for r in last_two):
                return True, "No progress in last 2 iterations"
        
        return False, ""
    
    def _save_iteration_result(self, result: IterationResult, workspace: Path):
        """Save iteration result to JSON"""
        result_file = workspace / 'iteration_result.json'
        with open(result_file, 'w') as f:
            json.dump(asdict(result), f, indent=2)
    
    def _save_final_report(self):
        """Save final iteration report"""
        report_file = self.workspace / 'iteration_report.json'
        
        report = {
            'total_iterations': self.iteration,
            'final_status': self.history[-1].status if self.history else 'unknown',
            'iterations': [asdict(r) for r in self.history]
        }
        
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2)
        
        print(f"\n📊 Final report saved to: {report_file}")


def main():
    parser = argparse.ArgumentParser(description='VHDL Iteration Orchestrator')
    parser.add_argument('--vhdl', required=True, help='VHDL module file')
    parser.add_argument('--testbench', help='Testbench file')
    parser.add_argument('--vivado-tcl', default='run.tcl', help='Vivado TCL script')
    parser.add_argument('--max-iterations', type=int, default=10, help='Maximum iterations')
    parser.add_argument('--workspace', default='workspace', help='Workspace directory')
    parser.add_argument('--vivado-cmd', default='vivado', help='Vivado command')
    
    args = parser.parse_args()
    
    config = {
        'vhdl_file': args.vhdl,
        'testbench_file': args.testbench,
        'vivado_tcl': args.vivado_tcl,
        'max_iterations': args.max_iterations,
        'workspace': args.workspace,
        'vivado_cmd': args.vivado_cmd
    }
    
    orchestrator = VHDLOrchestrator(config)
    success = orchestrator.run()
    
    return 0 if success else 1


if __name__ == '__main__':
    exit(main())
