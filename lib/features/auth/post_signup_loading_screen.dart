import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Clean loading screen shown after signup, before routing to the feed or
/// profile setup. Displays the app logo and name for branding.
class PostSignupLoadingScreen extends StatefulWidget {
  const PostSignupLoadingScreen({super.key});

  @override
  State<PostSignupLoadingScreen> createState() => _PostSignupLoadingScreenState();
}

class _PostSignupLoadingScreenState extends State<PostSignupLoadingScreen> {
  @override
  void initState() {
    super.initState();
    // Wait 2 seconds to show the splash, then navigate to feed
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/images/logo.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 24),
              // App name
              Text(
                'EnRICHed',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 40),
              // Loading indicator
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
