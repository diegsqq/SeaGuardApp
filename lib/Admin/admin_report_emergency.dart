import 'package:flutter/material.dart';

import 'emergency_level_selector.dart';
import 'share_location.dart' as sl;

class AdminReportEmergencyPage extends StatelessWidget {
  const AdminReportEmergencyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return EmergencyLevelSelectorScaffold(
      title: 'Report Emergency',
      headline: 'Dispatch an emergency alert',
      description: 'Pick the incident severity and continue to location sharing so nearby units can respond faster.',
      options: [
        EmergencyLevelOption(
          label: 'Safe',
          description: 'Broadcast a precautionary status update or a routine check when no immediate danger is present.',
          badge: 'Low alert',
          color: const Color(0xFF4BA4E6),
          icon: Icons.shield_outlined,
          onTap: () => _openShareLocation(context, 'Safe'),
        ),
        EmergencyLevelOption(
          label: 'Moderate',
          description: 'Use this when the situation is escalating and should be monitored or addressed soon.',
          badge: 'Heightened',
          color: const Color(0xFFD7B646),
          icon: Icons.warning_amber_rounded,
          onTap: () => _openShareLocation(context, 'Moderate'),
        ),
        EmergencyLevelOption(
          label: 'Danger',
          description: 'Trigger the highest-priority emergency flow for urgent incidents that may require immediate response.',
          badge: 'Critical',
          color: const Color(0xFFE55454),
          icon: Icons.priority_high_rounded,
          onTap: () => _openShareLocation(context, 'Danger'),
        ),
      ],
    );
  }

  void _openShareLocation(BuildContext context, String level) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => sl.ShareLocationPage(
          emergencyLevel: level,
          notifyAll: true,
        ),
      ),
    );
  }
}
