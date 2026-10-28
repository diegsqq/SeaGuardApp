import 'package:flutter/material.dart';

import 'emergency_level_selector.dart';

class ReportEmergency extends StatelessWidget {
  const ReportEmergency({super.key});

  @override
  Widget build(BuildContext context) {
    return EmergencyLevelSelectorScaffold(
      title: 'Report Emergency',
      headline: 'Choose alert level',
      description: 'Select the severity of the situation so the report can be handled with the right urgency.',
      options: [
        EmergencyLevelOption(
          label: 'Safe',
          description: 'Share a low-risk update or check-in without triggering a high-priority alert.',
          badge: 'Low alert',
          color: const Color(0xFF4BA4E6),
          icon: Icons.shield_outlined,
          onTap: () => _showUnavailableMessage(context),
        ),
        EmergencyLevelOption(
          label: 'Moderate',
          description: 'Use this for situations that need attention soon but are not immediately life-threatening.',
          badge: 'Watch closely',
          color: const Color(0xFFD7B646),
          icon: Icons.warning_amber_rounded,
          onTap: () => _showUnavailableMessage(context),
        ),
        EmergencyLevelOption(
          label: 'Danger',
          description: 'Send a critical emergency report when immediate assistance or escalation may be required.',
          badge: 'Critical',
          color: const Color(0xFFE55454),
          icon: Icons.priority_high_rounded,
          onTap: () => _showUnavailableMessage(context),
        ),
      ],
    );
  }

  void _showUnavailableMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Location sharing is unavailable (missing Maps API key).'),
      ),
    );
  }
}
