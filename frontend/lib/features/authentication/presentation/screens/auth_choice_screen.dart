import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignInAccount;
import '../../../../core/router/app_routes.dart';
import '../../../onboarding/presentation/controllers/profile_creation_controller.dart';
import '../controllers/auth_controller.dart';

enum _AuthMode { signUp, logIn }

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Premium palette for this screen only — kept local rather than added to
/// the shared AppColors design system, since these deep-wine/plum tones
/// are specific to this one "luxury matrimony" hero moment and aren't
/// meant to leak into the other ~40 screens that import AppColors.
class _Palette {
  _Palette._();

  static const Color plum = Color(0xFF3B1028);
  static const Color burgundy = Color(0xFF701B42);
  static const Color deepRose = Color(0xFFB51F59);
  static const Color primary = Color(0xFFD63F78);
  static const Color softPink = Color(0xFFF8DCE8);
  static const Color warmWhite = Color(0xFFFFF8FB);

  static const LinearGradient backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [plum, burgundy, Color(0xFF4A1230)],
    stops: [0.0, 0.55, 1.0],
  );

  static Color glassBorder = Colors.white.withValues(alpha: 0.16);
  static Color fieldFill = Colors.white.withValues(alpha: 0.05);
  static Color fieldBorder = softPink.withValues(alpha: 0.22);
  static Color fieldBorderFocused = primary.withValues(alpha: 0.9);
}

/// First screen after splash: an email+password sign-up-or-login form
/// (plus Google) — the gate every session starts from before any profile
/// questions.
///
/// This is a visual-only redesign — see AuthController /
/// ApiAuthRepository for the actual auth logic, which this screen calls
/// exactly as before (signup/login/signInWithGoogle, the same
/// isLoading/failure state contract).
class AuthChoiceScreen extends ConsumerStatefulWidget {
  const AuthChoiceScreen({super.key});

  @override
  ConsumerState<AuthChoiceScreen> createState() => _AuthChoiceScreenState();
}

class _AuthChoiceScreenState extends ConsumerState<AuthChoiceScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  _AuthMode _mode = _AuthMode.signUp;
  bool _obscurePassword = true;

  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  // A slow, continuous loop driving the floating hearts and the badge's
  // gentle pulse — deliberately long-period so it reads as "alive" rather
  // than as an obvious animation.
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  // Web-only: a click on Google's own rendered button (see
  // AuthController.googleWebButton) surfaces its result through this
  // stream rather than through a return value — the imperative `signIn()`
  // path other platforms use doesn't apply on web (see
  // GoogleAuthService's doc comments for why).
  StreamSubscription<GoogleSignInAccount?>? _googleWebSub;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _googleWebSub = ref
          .read(authControllerProvider.notifier)
          .googleAccountChanges
          .listen(_onGoogleWebAccount);
    }
  }

  Future<void> _onGoogleWebAccount(GoogleSignInAccount? account) async {
    if (account == null) return;
    final result = await ref
        .read(authControllerProvider.notifier)
        .completeGoogleSignInWithAccount(account);
    if (!mounted) return;
    await _handleGoogleResult(result);
  }

  @override
  void dispose() {
    _googleWebSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    _entrance.dispose();
    _ambient.dispose();
    super.dispose();
  }

  Future<void> _routeAfterAuth() async {
    // Returning users (an existing backend profile) skip onboarding
    // entirely; new users go through it as usual.
    final hasProfile = await ref
        .read(profileCreationControllerProvider.notifier)
        .loadExisting();
    if (!mounted) return;
    context.go(hasProfile ? AppRoutes.home : AppRoutes.profileFor);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final notifier = ref.read(authControllerProvider.notifier);

    final ok = _mode == _AuthMode.signUp
        ? await notifier.signup(email, password)
        : await notifier.login(email, password);
    if (!mounted) return;

    if (ok) {
      await _routeAfterAuth();
      return;
    }

    final failure = ref.read(authControllerProvider).failure;
    if (failure == null) return;

    if (_mode == _AuthMode.signUp && failure.code == 'already_registered') {
      setState(() => _mode = _AuthMode.logIn);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          duration: Duration(seconds: 3),
          content: Text(
              'You already have an account with this email — log in instead.'),
        ));
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 3),
          content: Text(failure.message)));
  }

  /// On web, Google's own rendered button (required — see
  /// GoogleAuthService.renderWebButton); everywhere else, the app's
  /// custom-styled button plus the imperative sign-in flow.
  Widget _buildGoogleButton(bool isLoading) {
    if (kIsWeb) {
      final webButton =
          ref.read(authControllerProvider.notifier).googleWebButton;
      if (webButton != null) {
        return SizedBox(height: 44, child: Center(child: webButton));
      }
    }
    return _GoogleButton(
      loading: isLoading,
      onTap: isLoading ? null : _signInWithGoogle,
    );
  }

  Future<void> _signInWithGoogle() async {
    final result =
        await ref.read(authControllerProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    await _handleGoogleResult(result);
  }

  /// Shared by both Google sign-in entry points: the imperative
  /// [_signInWithGoogle] (non-web) and [_onGoogleWebAccount] (web, via
  /// Google's own rendered button).
  Future<void> _handleGoogleResult(GoogleSignInResult result) async {
    switch (result) {
      case GoogleSignInResult.signedIn:
        await _routeAfterAuth();
      case GoogleSignInResult.otpRequired:
        // A first-time signup via the legacy passwordless path:
        // AuthController already sent the OTP and set pendingContact to
        // the Google account's email, so the OTP screen's existing
        // verifyOtp() call needs nothing Google-specific — this proceeds
        // exactly like any other signup from here.
        context.push(AppRoutes.otp);
      case GoogleSignInResult.failed:
        final failure = ref.read(authControllerProvider).failure;
        if (failure != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
                duration: const Duration(seconds: 3),
                content: Text(failure.message)));
        }
      case GoogleSignInResult.cancelled:
      // No error to show — the user closed the account picker.
    }
  }

  void _openForgotPassword() {
    context.push(AppRoutes.forgotPassword, extra: _emailController.text.trim());
  }

  String? _validateEmail(String? v) {
    final value = v?.trim() ?? '';
    if (value.isEmpty) return 'Enter your email address';
    if (!_emailPattern.hasMatch(value)) return 'Enter a valid email address';
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'Enter your password';
    if (_mode == _AuthMode.signUp && value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    return null;
  }

  Animation<double> _reveal(double start, double end) {
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _Palette.plum,
      body: SizedBox.expand(
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(gradient: _Palette.backdrop)),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _ambient,
                  builder: (context, _) => CustomPaint(
                    painter: _AmbientDecorPainter(progress: _ambient.value),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        24, 20, 24, 24 + bottomInset.clamp(0, 200)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 40,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Reveal(
                                animation: _reveal(0.0, 0.45),
                                child: _BrandHeader(ambient: _ambient),
                              ),
                              const SizedBox(height: 28),
                              _Reveal(
                                animation: _reveal(0.15, 0.55),
                                child: _ModeToggle(
                                  mode: _mode,
                                  onChanged: isLoading
                                      ? null
                                      : (mode) => setState(() => _mode = mode),
                                ),
                              ),
                              const SizedBox(height: 22),
                              _Reveal(
                                animation: _reveal(0.25, 0.7),
                                child: _GlassAuthCard(
                                  formKey: _formKey,
                                  mode: _mode,
                                  isLoading: isLoading,
                                  emailController: _emailController,
                                  passwordController: _passwordController,
                                  obscurePassword: _obscurePassword,
                                  onToggleObscure: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                  validateEmail: _validateEmail,
                                  validatePassword: _validatePassword,
                                  onSubmit: _submit,
                                  onForgotPassword: _openForgotPassword,
                                ),
                              ),
                              const SizedBox(height: 22),
                              _Reveal(
                                animation: _reveal(0.45, 0.85),
                                child: const _OrDivider(),
                              ),
                              const SizedBox(height: 18),
                              _Reveal(
                                animation: _reveal(0.55, 0.95),
                                child: _buildGoogleButton(isLoading),
                              ),
                              const SizedBox(height: 26),
                              _Reveal(
                                animation: _reveal(0.65, 1.0),
                                child: const _TrustFooter(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades + slides a child upward as [animation] runs 0 -> 1 — the shared
/// entrance treatment for every section on this screen (Phase 12's
/// staggered load sequence).
class _Reveal extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _Reveal({required this.animation, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1 - animation.value) * 18),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Glowing floating heart + "Vivah" wordmark + tagline + hairline divider.
class _BrandHeader extends StatelessWidget {
  final Animation<double> ambient;
  const _BrandHeader({required this.ambient});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedBuilder(
          animation: ambient,
          builder: (context, child) {
            // A gentle, slow breathing scale — not a bounce, not a spin.
            final pulse = 1.0 + 0.035 * math.sin(ambient.value * 2 * math.pi);
            return Transform.translate(
              offset: Offset(0, 3 * math.sin(ambient.value * 2 * math.pi)),
              child: Transform.scale(scale: pulse, child: child),
            );
          },
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                _Palette.primary.withValues(alpha: 0.55),
                _Palette.primary.withValues(alpha: 0.0),
              ]),
            ),
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.14),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: _Palette.primary.withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.favorite_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Vivah',
          style: GoogleFonts.fraunces(
            fontSize: 42,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Where Hearts Find Home',
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
            color: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        const SizedBox(height: 14),
        _HeartDivider(width: 96, opacity: 0.5),
      ],
    );
  }
}

class _HeartDivider extends StatelessWidget {
  final double width;
  final double opacity;
  const _HeartDivider({this.width = 120, this.opacity = 0.4});

  @override
  Widget build(BuildContext context) {
    final line = Container(
      width: width,
      height: 1,
      color: Colors.white.withValues(alpha: opacity),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Icon(Icons.favorite,
              size: 9,
              color: _Palette.softPink.withValues(alpha: opacity + 0.2)),
        ),
        line,
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final _AuthMode mode;
  final ValueChanged<_AuthMode>? onChanged;

  const _ModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _Palette.glassBorder, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                  child: _segment(context, 'Sign Up', _AuthMode.signUp,
                      Icons.favorite_border_rounded)),
              Expanded(
                  child: _segment(context, 'Log In', _AuthMode.logIn,
                      Icons.favorite_border_rounded)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(
      BuildContext context, String label, _AuthMode value, IconData icon) {
    final selected = mode == value;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [
                  _Palette.primary,
                  _Palette.deepRose,
                ])
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: _Palette.primary.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: Colors.white.withValues(alpha: selected ? 1 : 0.75)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white.withValues(alpha: selected ? 1 : 0.75),
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassAuthCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final _AuthMode mode;
  final bool isLoading;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final String? Function(String?) validateEmail;
  final String? Function(String?) validatePassword;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  const _GlassAuthCard({
    required this.formKey,
    required this.mode,
    required this.isLoading,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.validateEmail,
    required this.validatePassword,
    required this.onSubmit,
    required this.onForgotPassword,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(22, 34, 22, 22),
                decoration: BoxDecoration(
                  color: _Palette.burgundy.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14), width: 1.1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                    BoxShadow(
                      color: _Palette.primary.withValues(alpha: 0.12),
                      blurRadius: 40,
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: Form(
                  key: formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          mode == _AuthMode.signUp
                              ? 'Begin your journey to a meaningful connection.'
                              : 'Continue your journey to meaningful connections.',
                          key: ValueKey(mode),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _PremiumTextField(
                        controller: emailController,
                        label: 'Email',
                        hint: 'you@example.com',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        validator: validateEmail,
                      ),
                      const SizedBox(height: 14),
                      _PremiumTextField(
                        controller: passwordController,
                        label: 'Password',
                        hint: mode == _AuthMode.signUp
                            ? 'At least 8 characters'
                            : null,
                        icon: Icons.lock_outline_rounded,
                        obscureText: obscurePassword,
                        autofillHints: [
                          mode == _AuthMode.signUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        validator: validatePassword,
                        trailing: IconButton(
                          splashRadius: 20,
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          onPressed: onToggleObscure,
                        ),
                      ),
                      if (mode == _AuthMode.logIn)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: isLoading ? null : onForgotPassword,
                            style: TextButton.styleFrom(
                              foregroundColor: _Palette.softPink,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                            child: Text('Forgot password?',
                                style: GoogleFonts.inter(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                          ),
                        )
                      else
                        const SizedBox(height: 6),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.shield_outlined,
                              size: 14,
                              color: _Palette.softPink.withValues(alpha: 0.75)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Your privacy and data are secure with us.',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _PrimaryCTAButton(
                        loading: isLoading,
                        label: mode == _AuthMode.signUp
                            ? 'Create Account'
                            : 'Log In',
                        onTap: isLoading ? null : onSubmit,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        // Small circular heart badge overlapping the card's top edge —
        // the visual link between the brand header above and the form.
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [_Palette.primary, _Palette.deepRose],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.5), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: _Palette.primary.withValues(alpha: 0.55),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Icons.favorite, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

/// A single email/password field with a circular icon chip, floating
/// label, and its own focus-driven glow — self-contained so the parent
/// doesn't need to manage a FocusNode per field.
class _PremiumTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final String? Function(String?) validator;
  final Widget? trailing;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.trailing,
  });

  @override
  State<_PremiumTextField> createState() => _PremiumTextFieldState();
}

class _PremiumTextFieldState extends State<_PremiumTextField> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _focused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: _Palette.fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _focused ? _Palette.fieldBorderFocused : _Palette.fieldBorder,
          width: _focused ? 1.4 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: _Palette.primary.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: _focusNode,
        obscureText: widget.obscureText,
        keyboardType: widget.keyboardType,
        autofillHints: widget.autofillHints,
        validator: widget.validator,
        style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
        cursorColor: _Palette.softPink,
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
          labelText: widget.label,
          hintText: widget.hint,
          labelStyle: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.65), fontSize: 14),
          floatingLabelStyle: GoogleFonts.inter(
              color: _Palette.softPink,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          hintStyle: GoogleFonts.inter(
              color: Colors.white.withValues(alpha: 0.35), fontSize: 13.5),
          errorStyle:
              GoogleFonts.inter(color: const Color(0xFFFFB4C6), fontSize: 11.5),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          prefixIcon: Padding(
            padding: const EdgeInsets.all(11),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    _Palette.primary.withValues(alpha: _focused ? 0.32 : 0.18),
              ),
              padding: const EdgeInsets.all(8),
              child: Icon(widget.icon,
                  size: 16,
                  color: _focused
                      ? Colors.white
                      : _Palette.softPink.withValues(alpha: 0.9)),
            ),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 44, minHeight: 44),
          suffixIcon: widget.trailing,
        ),
      ),
    );
  }
}

class _PrimaryCTAButton extends StatefulWidget {
  final String label;
  final bool loading;
  final VoidCallback? onTap;

  const _PrimaryCTAButton(
      {required this.label, required this.loading, required this.onTap});

  @override
  State<_PrimaryCTAButton> createState() => _PrimaryCTAButtonState();
}

class _PrimaryCTAButtonState extends State<_PrimaryCTAButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_Palette.primary, _Palette.deepRose],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: _Palette.primary
                    .withValues(alpha: widget.onTap == null ? 0.15 : 0.5),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.label,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.favorite, size: 16, color: Colors.white),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.favorite,
                  size: 10, color: _Palette.softPink.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('or',
                  style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        line,
      ],
    );
  }
}

class _GoogleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool loading;

  const _GoogleButton({required this.onTap, required this.loading});

  @override
  State<_GoogleButton> createState() => _GoogleButtonState();
}

class _GoogleButtonState extends State<_GoogleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:
          widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: _Palette.warmWhite,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: _Palette.burgundy),
                )
              else
                const _GoogleMark(),
              const SizedBox(width: 12),
              Text(
                'Continue with Google',
                style: GoogleFonts.inter(
                  color: const Color(0xFF3C2430),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact "G" brand mark — this repo has no Google logo asset/SVG, so
/// rather than fetch one at build time this renders a simple, safe
/// letterform mark instead of risking a hand-drawn multi-color logo
/// rendering incorrectly.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Text(
        'G',
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF4285F4),
          height: 1,
        ),
      ),
    );
  }
}

class _TrustFooter extends StatelessWidget {
  const _TrustFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.favorite_border_rounded,
            size: 13, color: _Palette.softPink.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Helping hearts find meaningful connections',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the subtle background atmosphere: two soft radial glows and a
/// handful of slowly drifting, low-opacity heart silhouettes. Pure
/// CustomPainter (not a stack of animated widgets) so this whole layer is
/// one repaint per frame instead of several — cheap enough to run
/// continuously behind interactive form fields.
class _AmbientDecorPainter extends CustomPainter {
  final double progress; // 0..1, looping

  _AmbientDecorPainter({required this.progress});

  static const _hearts = [
    _FloatingHeart(
        dx: 0.12,
        baseDy: 0.14,
        size: 14,
        opacity: 0.10,
        phase: 0.0,
        speed: 1.0),
    _FloatingHeart(
        dx: 0.85,
        baseDy: 0.10,
        size: 10,
        opacity: 0.08,
        phase: 0.3,
        speed: 0.7),
    _FloatingHeart(
        dx: 0.78,
        baseDy: 0.30,
        size: 18,
        opacity: 0.07,
        phase: 0.6,
        speed: 1.3),
    _FloatingHeart(
        dx: 0.08,
        baseDy: 0.42,
        size: 22,
        opacity: 0.06,
        phase: 0.15,
        speed: 0.5),
    _FloatingHeart(
        dx: 0.90,
        baseDy: 0.55,
        size: 12,
        opacity: 0.09,
        phase: 0.75,
        speed: 0.9),
    _FloatingHeart(
        dx: 0.15,
        baseDy: 0.72,
        size: 16,
        opacity: 0.07,
        phase: 0.5,
        speed: 0.6),
    _FloatingHeart(
        dx: 0.82,
        baseDy: 0.80,
        size: 20,
        opacity: 0.05,
        phase: 0.9,
        speed: 1.1),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Two soft blurred radial glows for depth.
    final glow1 = Paint()
      ..shader = RadialGradient(
        colors: [
          _Palette.primary.withValues(alpha: 0.22),
          _Palette.primary.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.2, size.height * 0.12),
          radius: size.width * 0.55))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(
        Offset(size.width * 0.2, size.height * 0.12), size.width * 0.55, glow1);

    final glow2 = Paint()
      ..shader = RadialGradient(
        colors: [
          _Palette.deepRose.withValues(alpha: 0.18),
          _Palette.deepRose.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.85, size.height * 0.75),
          radius: size.width * 0.6))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70);
    canvas.drawCircle(
        Offset(size.width * 0.85, size.height * 0.75), size.width * 0.6, glow2);

    for (final h in _hearts) {
      final t = (progress * h.speed + h.phase) % 1.0;
      final floatOffset = math.sin(t * 2 * math.pi) * 10;
      final opacity = h.opacity * (0.6 + 0.4 * math.sin(t * 2 * math.pi + 1));
      _drawHeart(
        canvas,
        Offset(size.width * h.dx, size.height * h.baseDy + floatOffset),
        h.size,
        Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final path = Path();
    final w = size;
    path.moveTo(center.dx, center.dy + w * 0.3);
    path.cubicTo(
      center.dx - w,
      center.dy - w * 0.4,
      center.dx - w * 0.5,
      center.dy - w,
      center.dx,
      center.dy - w * 0.25,
    );
    path.cubicTo(
      center.dx + w * 0.5,
      center.dy - w,
      center.dx + w,
      center.dy - w * 0.4,
      center.dx,
      center.dy + w * 0.3,
    );
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AmbientDecorPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _FloatingHeart {
  final double dx; // 0..1 fraction of width
  final double baseDy; // 0..1 fraction of height
  final double size;
  final double opacity;
  final double phase; // 0..1 offset into the loop
  final double speed; // relative loop speed

  const _FloatingHeart({
    required this.dx,
    required this.baseDy,
    required this.size,
    required this.opacity,
    required this.phase,
    required this.speed,
  });
}
