import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/loading_delay.dart';

const Color _brandPrimary = Color(0xFF0F2548);

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;

  bool obscureCurrent = true;
  bool obscureNew = true;
  bool obscureConfirm = true;

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => isLoading = true);
    final loadingDelay = Future<void>.delayed(appLoadingDelay);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.noUserIsCurrentlySignedIn)),
        );
        return;
      }

      final email = user.email;
      if (email == null || email.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.userDoesNotHaveAnEmailOnRecord)),
        );
        return;
      }

      // Re-authenticate
      final cred = EmailAuthProvider.credential(
        email: email,
        password: currentPasswordController.text.trim(),
      );

      await user.reauthenticateWithCredential(cred);

      await user.updatePassword(newPasswordController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.passwordUpdatedSuccessfully),
          backgroundColor: _brandPrimary,
        ),
      );

      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String errorMessage = AppLocalizations.of(context)!.errorChangingPassword;
      if (e.code == 'wrong-password') {
        errorMessage = AppLocalizations.of(context)!.currentPasswordIsIncorrect;
      } else if (e.code == 'weak-password') {
        errorMessage = AppLocalizations.of(context)!.passwordShouldBeAtLeast6Characters;
      } else if (e.code == 'requires-recent-login') {
        errorMessage = AppLocalizations.of(context)!.pleaseLogInAgainBeforeChangingYourPasswordForSecurityReasons;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${AppLocalizations.of(context)!.unexpectedError}: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      await loadingDelay;
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 560;
    final maxWidth = isWide ? 460.0 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.changePassword,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF102A43),
            fontSize: 28,
          ),
        ),
        backgroundColor: const Color(0xFFF3F7FC),
        foregroundColor: const Color(0xFF102A43),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.white, Color(0xFFF0F7FF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD7E6F5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F2548).withValues(alpha: 0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F2FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_reset_outlined,
                        color: Color(0xFF154A79),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Password security',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF102A43),
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Set a strong password to protect your account.',
                            style: TextStyle(
                              color: Color(0xFF486581),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildPasswordField(
                      controller: currentPasswordController,
                      label: AppLocalizations.of(context)!.currentPassword,
                      obscureText: obscureCurrent,
                      onToggleVisibility: () =>
                          setState(() => obscureCurrent = !obscureCurrent),
                      prefixIcon: Icons.key_rounded,
                      enforceMinLength: false,
                    ),
                    const SizedBox(height: 14),
                    _buildPasswordField(
                      controller: newPasswordController,
                      label: AppLocalizations.of(context)!.newPassword,
                      obscureText: obscureNew,
                      onToggleVisibility: () =>
                          setState(() => obscureNew = !obscureNew),
                      prefixIcon: Icons.lock_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    _buildPasswordField(
                      controller: confirmPasswordController,
                      label: AppLocalizations.of(context)!.confirmNewPassword,
                      obscureText: obscureConfirm,
                      onToggleVisibility: () =>
                          setState(() => obscureConfirm = !obscureConfirm),
                      prefixIcon: Icons.check_circle_outline_rounded,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return AppLocalizations.of(context)!.pleaseConfirmYourNewPassword;
                        }
                        if (value != newPasswordController.text) {
                          return AppLocalizations.of(context)!.passwordsDoNotMatch;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFC9E0FF)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 18,
                            color: Color(0xFF1D4E89),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Use at least 6 characters with a mix of letters and numbers.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF1D4E89),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: isLoading ? null : _changePassword,
                        style: FilledButton.styleFrom(
                          backgroundColor: _brandPrimary,
                          disabledBackgroundColor: _brandPrimary.withValues(
                            alpha: 0.65,
                          ),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Text(
                                AppLocalizations.of(context)!.updatePassword,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required IconData prefixIcon,
    bool enforceMinLength = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator ??
          (value) {
            if (value == null || value.isEmpty) {
              return '${AppLocalizations.of(context)!.pleaseEnter} $label';
            }
            if (enforceMinLength && value.length < 6) {
              return AppLocalizations.of(context)!.passwordMustBeAtLeast6Characters;
            }
            return null;
          },
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF486581),
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 17,
        ),
        prefixIcon: Icon(
          prefixIcon,
          size: 19,
          color: const Color(0xFF627D98),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFBCCCDC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF2F6FB0), width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD92D20)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFD92D20), width: 1.4),
        ),
        suffixIcon: IconButton(
          icon: Icon(
            obscureText ? Icons.visibility_off : Icons.visibility,
            color: const Color(0xFF627D98),
          ),
          onPressed: onToggleVisibility,
        ),
      ),
    );
  }
}
