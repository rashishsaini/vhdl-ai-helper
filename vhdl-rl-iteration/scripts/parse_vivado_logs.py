#!/usr/bin/env python3
"""
Parse Vivado logs and categorize errors for iteration decisions.

Categorizes errors into:
- FIXABLE: Syntax errors, missing signals, simple type issues
- TESTBENCH: Test vector problems, testbench-specific issues  
- ARCHITECTURE: Design-level problems requiring human expertise
- PHYSICS: Timing/resource constraints beyond code fixes
"""

import re
import json
import argparse
from typing import List, Dict, Any
from dataclasses import dataclass, asdict
from enum import Enum


class ErrorCategory(Enum):
    """Error categories for iteration decisions"""
    FIXABLE = "FIXABLE"  # Can be fixed by AI iteration
    TESTBENCH = "TESTBENCH"  # Testbench issues
    ARCHITECTURE = "ARCHITECTURE"  # Needs human design decisions
    PHYSICS = "PHYSICS"  # Physical/resource constraints
    UNKNOWN = "UNKNOWN"  # Cannot categorize


@dataclass
class ParsedError:
    """Structured error representation"""
    line_number: int
    severity: str
    message: str
    file: str
    category: ErrorCategory
    fixable: bool
    confidence: int  # 0-100
    context: str = ""


class VivadoLogParser:
    """Parse Vivado logs and categorize errors"""
    
    # Patterns for FIXABLE errors
    FIXABLE_PATTERNS = [
        r"missing semicolon",
        r"syntax error",
        r"unexpected token",
        r"missing 'end'",
        r"undeclared identifier",
        r"type mismatch",
        r"missing signal declaration",
        r"sensitivity list",
        r"missing library",
        r"missing package",
    ]
    
    # Patterns for TESTBENCH errors
    TESTBENCH_PATTERNS = [
        r"test.*failed",
        r"assertion.*failed",
        r"testbench",
        r"tb_.*",
        r"simulation.*error",
        r"expected.*got",
        r"mismatch.*test",
    ]
    
    # Patterns for ARCHITECTURE errors (human needed)
    ARCHITECTURE_PATTERNS = [
        r"timing.*violation",
        r"setup.*violation",
        r"hold.*violation",
        r"resource.*exceeded",
        r"insufficient.*resources",
        r"cannot.*implement",
        r"unroutable",
        r"clock.*skew",
        r"metastability",
    ]
    
    # Patterns for PHYSICS errors (fundamental limits)
    PHYSICS_PATTERNS = [
        r"negative.*slack",
        r"timing.*closure.*failed",
        r"place.*failed",
        r"route.*failed",
        r"LUT.*exceeded",
        r"BRAM.*exceeded",
        r"DSP.*exceeded",
        r"critical.*path",
    ]
    
    def __init__(self, log_path: str):
        self.log_path = log_path
        self.errors: List[ParsedError] = []
        
    def parse(self) -> List[ParsedError]:
        """Parse log file and extract errors"""
        with open(self.log_path, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
        
        for i, line in enumerate(lines):
            if self._is_error_line(line):
                error = self._parse_error_line(line, i, lines)
                if error:
                    self.errors.append(error)
        
        return self.errors
    
    def _is_error_line(self, line: str) -> bool:
        """Check if line contains error marker"""
        error_markers = ['ERROR:', 'CRITICAL WARNING:', 'FATAL:']
        return any(marker in line.upper() for marker in error_markers)
    
    def _parse_error_line(self, line: str, line_num: int, all_lines: List[str]) -> ParsedError:
        """Parse a single error line"""
        # Extract severity
        severity = 'ERROR'
        if 'CRITICAL WARNING' in line.upper():
            severity = 'CRITICAL WARNING'
        elif 'FATAL' in line.upper():
            severity = 'FATAL'
        
        # Extract file and line if present
        file_match = re.search(r'(\w+\.vhd?):(\d+)', line)
        file = file_match.group(1) if file_match else 'unknown'
        error_line = int(file_match.group(2)) if file_match else 0
        
        # Get context (next 3 lines)
        context_lines = all_lines[line_num+1:line_num+4]
        context = ''.join(context_lines).strip()
        
        # Categorize the error
        category, confidence = self._categorize_error(line + ' ' + context)
        
        return ParsedError(
            line_number=error_line,
            severity=severity,
            message=line.strip(),
            file=file,
            category=category,
            fixable=category in [ErrorCategory.FIXABLE, ErrorCategory.TESTBENCH],
            confidence=confidence,
            context=context
        )
    
    def _categorize_error(self, text: str) -> tuple[ErrorCategory, int]:
        """Categorize error and return confidence"""
        text_lower = text.lower()
        
        # Check each category with confidence scoring
        physics_score = sum(1 for p in self.PHYSICS_PATTERNS if re.search(p, text_lower))
        if physics_score > 0:
            return ErrorCategory.PHYSICS, min(90 + physics_score * 5, 100)
        
        arch_score = sum(1 for p in self.ARCHITECTURE_PATTERNS if re.search(p, text_lower))
        if arch_score > 0:
            return ErrorCategory.ARCHITECTURE, min(85 + arch_score * 5, 100)
        
        tb_score = sum(1 for p in self.TESTBENCH_PATTERNS if re.search(p, text_lower))
        if tb_score > 0:
            return ErrorCategory.TESTBENCH, min(80 + tb_score * 5, 100)
        
        fix_score = sum(1 for p in self.FIXABLE_PATTERNS if re.search(p, text_lower))
        if fix_score > 0:
            return ErrorCategory.FIXABLE, min(75 + fix_score * 5, 100)
        
        return ErrorCategory.UNKNOWN, 50
    
    def get_summary(self) -> Dict[str, Any]:
        """Get categorized summary of errors"""
        summary = {
            'total_errors': len(self.errors),
            'by_category': {},
            'fixable_count': sum(1 for e in self.errors if e.fixable),
            'should_continue': False,
            'recommendation': ''
        }
        
        # Count by category
        for cat in ErrorCategory:
            count = sum(1 for e in self.errors if e.category == cat)
            if count > 0:
                summary['by_category'][cat.value] = count
        
        # Decision logic
        physics_count = summary['by_category'].get('PHYSICS', 0)
        arch_count = summary['by_category'].get('ARCHITECTURE', 0)
        fixable_count = summary['fixable_count']
        
        if physics_count > 0:
            summary['recommendation'] = 'STOP: Physical constraints detected - needs architectural redesign'
        elif arch_count > 0:
            summary['recommendation'] = 'STOP: Architecture issues detected - needs human design review'
        elif fixable_count > 0:
            summary['should_continue'] = True
            summary['recommendation'] = f'CONTINUE: {fixable_count} fixable errors found'
        else:
            summary['recommendation'] = 'UNKNOWN: Cannot categorize errors clearly'
        
        return summary
    
    def to_json(self) -> str:
        """Export errors to JSON"""
        output = {
            'summary': self.get_summary(),
            'errors': [asdict(e) for e in self.errors]
        }
        # Convert Enum to string for JSON serialization
        for error in output['errors']:
            error['category'] = error['category'].value
        return json.dumps(output, indent=2)


def main():
    parser = argparse.ArgumentParser(description='Parse Vivado logs and categorize errors')
    parser.add_argument('log_file', help='Path to Vivado log file')
    parser.add_argument('--output', '-o', help='Output JSON file (default: stdout)')
    parser.add_argument('--summary-only', action='store_true', help='Only show summary')
    
    args = parser.parse_args()
    
    # Parse log
    log_parser = VivadoLogParser(args.log_file)
    errors = log_parser.parse()
    
    if args.summary_only:
        summary = log_parser.get_summary()
        print(json.dumps(summary, indent=2))
    else:
        output_json = log_parser.to_json()
        if args.output:
            with open(args.output, 'w') as f:
                f.write(output_json)
            print(f"Wrote {len(errors)} errors to {args.output}")
        else:
            print(output_json)
    
    # Return exit code based on recommendation
    summary = log_parser.get_summary()
    if not summary['should_continue']:
        return 1
    return 0


if __name__ == '__main__':
    exit(main())
