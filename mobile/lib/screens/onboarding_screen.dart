import 'package:dio/dio.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:nexus/config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    required this.termsVersion,
    required this.onComplete,
    super.key,
  });

  final String termsVersion;
  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _selectedBranch = 'CSBS';
  int _selectedYear = 1;
  int _selectedAge = 18;
  bool _isLoading = false;

  final List<String> _branches = [
    'CSBS',
    'CSE',
    'ECE',
    'ME',
    'CE',
    'IT',
    'EE',
    'EB',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submitOnboarding() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final config = AppConfig.current;
      final dio = Dio();

      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception('Session expired. Please sign in again.');
      }

      final appCheckToken = await FirebaseAppCheck.instance.getToken();

      final response = await dio.post<Map<String, dynamic>>(
        '${config.backendUrl}/api/v1/auth/complete-onboarding',
        data: {
          'name': _nameController.text.trim(),
          'branch': _selectedBranch,
          'year': _selectedYear,
          'age': _selectedAge,
          'accepted_terms_version': widget.termsVersion,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'X-Firebase-AppCheck': appCheckToken ?? '',
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        widget.onComplete();
      } else {
        final errorMsg =
            response.data?['detail'] ?? 'Failed to complete onboarding.';
        throw Exception(errorMsg);
      }
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFD32F2F),
            content: Text(
              'Onboarding failed: ${e.toString().replaceAll('Exception:', '').trim()}',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D0F),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Welcome to Nexus'.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: Color(0xFF0D9488),
                    ),
                  ).animate().fade().scale(duration: 400.ms),
                  const SizedBox(height: 8),
                  const Text(
                    'Tell us about yourself',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.white,
                    ),
                  ).animate().fade(delay: 100.ms),
                  const SizedBox(height: 24),
                  // Tech-Teal Card containing the fields
                  Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111619),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0x1F0D9488)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name Field
                            const Text(
                              'FULL NAME',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: Color(0x99FFFFFF),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _nameController,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Enter your name',
                                hintStyle: const TextStyle(
                                  color: Color(0x4DFFFFFF),
                                ),
                                filled: true,
                                fillColor: const Color(0xFF090D0F),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0x1F0D9488),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD32F2F),
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD32F2F),
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().length < 2) {
                                  return 'Name must be at least 2 characters.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            // Branch Field
                            const Text(
                              'ENGINEERING BRANCH',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: Color(0x99FFFFFF),
                              ),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedBranch,
                              dropdownColor: const Color(0xFF111619),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: const Color(0xFF090D0F),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0x1F0D9488),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ),
                              items: _branches.map((branch) {
                                return DropdownMenuItem(
                                  value: branch,
                                  child: Text(branch),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedBranch = value;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 20),

                            // Academic Year Field
                            const Text(
                              'ACADEMIC YEAR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: Color(0x99FFFFFF),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(5, (index) {
                                final year = index + 1;
                                final isSelected = _selectedYear == year;
                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedYear = year;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: 250.ms,
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected
                                            ? const Color(0xFF0D9488)
                                            : const Color(0x1AFFFFFF),
                                      ),
                                      color: isSelected
                                          ? const Color(0x260D9488)
                                          : const Color(0xFF090D0F),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$year',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? Colors.white
                                              : const Color(0x99FFFFFF),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 20),

                            // Age Field
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'AGE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.5,
                                    color: Color(0x99FFFFFF),
                                  ),
                                ),
                                Text(
                                  '$_selectedAge years old',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0D9488),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: const Color(0xFF0D9488),
                                inactiveTrackColor: const Color(0x1AFFFFFF),
                                thumbColor: Colors.white,
                                overlayColor: const Color(0x260D9488),
                                valueIndicatorColor: const Color(0xFF0D9488),
                                valueIndicatorTextStyle: const TextStyle(
                                  color: Colors.white,
                                ),
                              ),
                              child: Slider(
                                value: _selectedAge.toDouble(),
                                min: 18,
                                max: 27,
                                divisions: 9,
                                label: '$_selectedAge',
                                onChanged: (value) {
                                  setState(() {
                                    _selectedAge = value.round();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                      .animate()
                      .fade(delay: 200.ms)
                      .slideY(begin: 0.1, end: 0, duration: 400.ms),
                  const SizedBox(height: 32),
                  // Submit Button
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF0D9488),
                        ),
                      ),
                    )
                  else
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _submitOnboarding,
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x260D9488),
                                blurRadius: 15,
                                spreadRadius: 1,
                              ),
                            ],
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF0D9488),
                                Color(0xFF0F766E),
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              'Complete Onboarding',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ).animate().fade(delay: 300.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
