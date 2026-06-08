import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Onboarding fields shown only for the Nexus-MEC (college) flavor.
///
/// Collects branch and college year.
class MECOnboardingFields extends StatefulWidget {
  const MECOnboardingFields({
    required this.onChanged,
    super.key,
  });

  /// Called whenever branch or year changes.
  final void Function({
    required String branch,
    required int year,
  })
  onChanged;

  @override
  State<MECOnboardingFields> createState() => _MECOnboardingFieldsState();
}

class _MECOnboardingFieldsState extends State<MECOnboardingFields> {
  static const _branches = [
    'CSBS',
    'CSE',
    'ECE',
    'EE',
    'EB',
    'ME',
  ];

  static const _years = [1, 2, 3, 4];

  String _selectedBranch = 'CSBS';
  int _selectedYear = 1;

  void _notify() {
    widget.onChanged(
      branch: _selectedBranch,
      year: _selectedYear,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Branch ───────────────────────────────────────────────────────────
        const Text(
          'BRANCH / DEPARTMENT',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Color(0x99FFFFFF),
          ),
        ),
        const SizedBox(height: 8),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          children: _branches.map((b) {
            final isSelected = _selectedBranch == b;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedBranch = b);
                _notify();
              },
              child: AnimatedContainer(
                duration: 200.ms,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFF7597)
                        : const Color(0x1AFFFFFF),
                  ),
                  color: isSelected
                      ? const Color(0x26FF7597)
                      : const Color(0xFF0B0D13),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFFFF7597).withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  b,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : const Color(0x99FFFFFF),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),

        // ── Year ─────────────────────────────────────────────────────────────
        const Text(
          'COLLEGE YEAR',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Color(0x99FFFFFF),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (int i = 0; i < _years.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedYear = _years[i]);
                    _notify();
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedYear == _years[i]
                            ? const Color(0xFFFF7597)
                            : const Color(0x1AFFFFFF),
                      ),
                      color: _selectedYear == _years[i]
                          ? const Color(0x26FF7597)
                          : const Color(0xFF0B0D13),
                    ),
                    child: Text(
                      'Year ${_years[i]}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _selectedYear == _years[i]
                            ? Colors.white
                            : const Color(0x99FFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ).animate().fade(delay: 250.ms).slideY(begin: 0.05, end: 0, duration: 350.ms);
  }
}
