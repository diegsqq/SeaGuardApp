import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'change_username.dart';
import 'change_password.dart';
import '../../l10n/app_localizations.dart';

const Color _brandPrimary = Color(0xFF0F2548);

class AccountManagementPage extends StatefulWidget {
  const AccountManagementPage({super.key});

  @override
  State<AccountManagementPage> createState() => _AccountManagementPageState();
}

class _AccountManagementPageState extends State<AccountManagementPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isDeleting = false;

  // 🔥 Function to delete user account after re-authentication
  Future<void> _deleteAccount(String password) async {
    setState(() => isDeleting = true);

    try {
      final user = _auth.currentUser;

      if (user == null || user.email == null) {
        throw Exception("User not found");
      }

      // Re-authenticate before deletion
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      // Delete the user
      await user.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.accountDeletedSuccessfullyItWillBePermanentlyRemovedAfter30Days,
          ),
          backgroundColor: _brandPrimary,
          duration: const Duration(seconds: 4),
        ),
      );

      await _auth.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String message = "${AppLocalizations.of(context)!.errorDeletingAccount}: ${e.message}";
      if (e.code == 'wrong-password') {
        message = AppLocalizations.of(context)!.incorrectPasswordPleaseTryAgain;
      } else if (e.code == 'requires-recent-login') {
        message = AppLocalizations.of(context)!.forSecurityPleaseLogInAgainBeforeDeletingYourAccount;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("${AppLocalizations.of(context)!.unexpectedError}: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => isDeleting = false);
      }
    }
  }

  // 🔤 Navigation functions
  Future<void> _navigateToChangeUsername() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangeUsernamePage()),
    );
  }

  Future<void> _navigateToChangePassword() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
    );
  }


  // 🧨 Confirm delete dialog
  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.confirmDelete),
        content: Text(
          AppLocalizations.of(context)!.areYouSureYouWantToDeleteYourAccountThisActionCannotBeUndone,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showPasswordPrompt();
            },
            child: Text(
              AppLocalizations.of(context)!.yesDelete,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // 🔑 Password confirmation dialog with eye icon
  void _showPasswordPrompt() {
    final passwordController = TextEditingController();
    bool obscure = true;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) => AlertDialog(
            title: Text(AppLocalizations.of(context)!.enterPassword),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)!.pleaseConfirmYourPasswordToProceedWithAccountDeletionNoteYourAccountWillBePermanentlyDeletedAfter30Days,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.password,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey.shade700,
                      ),
                      onPressed: () {
                        setStateDialog(() => obscure = !obscure);
                      },
                    ),
                  ),
                ),
              ],
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context)!.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (passwordController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.of(context)!.pleaseEnterYourPassword),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  _deleteAccount(passwordController.text.trim());
                },
                child: Text(
                  AppLocalizations.of(context)!.confirm,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.accountManagement,
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
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        children: [
          const _SectionHeader(
            icon: Icons.admin_panel_settings_outlined,
            title: 'Security Settings',
            subtitle: 'Manage your username and password',
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.person_outline,
            title: AppLocalizations.of(context)!.changeUsername,
            subtitle: 'Edit your display and login name',
            onTap: _navigateToChangeUsername,
          ),
          const SizedBox(height: 12),
          _ActionTile(
            icon: Icons.lock_outline_rounded,
            title: AppLocalizations.of(context)!.changePassword,
            subtitle: 'Update your password for better account security',
            onTap: _navigateToChangePassword,
          ),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F4),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF5C7C3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Danger Zone',
                  style: TextStyle(
                    color: Color(0xFFB42318),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Deleting your account starts a permanent removal process.',
                  style: TextStyle(
                    color: Color(0xFF7A271A),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: isDeleting ? null : _confirmDeleteAccount,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB42318),
                    minimumSize: const Size(double.infinity, 52),
                    side: const BorderSide(color: Color(0xFFEF6F66)),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: isDeleting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Color(0xFFB42318),
                            strokeWidth: 2.2,
                          ),
                        )
                      : const Icon(Icons.delete_outline_rounded),
                  label: Text(
                    AppLocalizations.of(context)!.deleteAccount,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE2EEF9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF154A79), size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF102A43),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF486581),
                    fontSize: 12.8,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD7E6F5)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F2548).withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF3FF),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: const Color(0xFF154A79), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF102A43),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF627D98),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF829AB1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
