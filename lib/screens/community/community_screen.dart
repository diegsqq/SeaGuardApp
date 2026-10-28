import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../profile/profile_page.dart';
import '../dashboard/navbar_screen.dart';
import 'community_engagement.dart';
import '../../utils/responsive.dart';
import '../../utils/community_moderation.dart';

class _CommentView {
  final String id;
  final String source; // 'sub' or 'root'
  final String author;
  final String authorId;
  final String text;
  final DateTime? createdAt;
  final String? profileImageBase64;
  final String? profileImageUrl;
  final String? authPhotoUrl;

  _CommentView({
    required this.id,
    required this.source,
    required this.author,
    required this.authorId,
    required this.text,
    required this.createdAt,
    this.profileImageBase64,
    this.profileImageUrl,
    this.authPhotoUrl,
  });
}

class CommunityScreen extends StatefulWidget {
  final String? initialPostId;

  const CommunityScreen({super.key, this.initialPostId});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  int _selectedIndex = 1;
  static const Color _pageTop = Color(0xFFEAF4FF);
  static const Color _pageBottom = Color(0xFFF8FCFF);
  static const Color _ink = Color(0xFF102A43);
  static const Color _subtleInk = Color(0xFF486581);
  static const double _feedMaxWidth = 720;
  late Stream<QuerySnapshot<Map<String, dynamic>>> postsStream =
      FirebaseFirestore.instance
          .collection('community_posts')
          .snapshots();
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _singlePostStream;
  String selectedCategory = "All";
  String? _userId;
  String? _profileImageUrl;
  String? _profileImageBase64;
  String? _authPhotoUrl;
  String? _userName;
  String? _userRole;
  String? _initialPostId;
  final Map<String, Map<String, String?>> _userProfiles = {};
  final Map<String, StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>> _profileListeners = {};
  final Set<String> _scheduledProfileSubscriptions = {};
  final Set<String> _scheduledAdminPostNotifications = {};
  final Set<String> _scheduledPostStatusNotifications = {};

  final List<String> categories = [
    "All",
    "Resident",
    "Fisherman",
    "BFAR",
    "PCG",
    "My Posts",
  ];

  Map<String, bool> likedPosts = {};
  Map<String, int> likeCounts = {};
  Map<String, int> commentCounts = {};
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _roleBucket(String? raw) {
    final r = (raw ?? '').toLowerCase().trim();
    if (r.contains('pcg') || r.contains('web-admin') || r.contains('sub-admin')) return 'pcg';
    if (r.contains('bfar')) return 'bfar';
    if (r.contains('fish')) return 'fisherman';
    if (r.contains('admin')) return 'admin';
    if (r.contains('resident')) return 'resident';
    return 'resident';
  }

  String _roleLabel(String? raw) {
    final bucket = _roleBucket(raw);
    final lower = (raw ?? '').toLowerCase();
    switch (bucket) {
      case 'pcg':
        if (lower.contains('sub') || lower.contains('web-admin')) {
          return 'PCG Sub-Admin';
        }
        return 'PCG';
      case 'bfar':
        if (lower.contains('web-admin')) return 'BFAR Web Admin';
        return 'BFAR';
      case 'fisherman':
        return 'Fisherman';
      case 'admin':
        return 'Admin';
      default:
        return 'Resident';
    }
  }

  bool _canSeeAnonymousIdentity() {
    final role = (_userRole ?? '').toLowerCase();
    return role.contains('admin') ||
        role.contains('bfar') ||
        role.contains('pcg') ||
        role.contains('web-admin');
  }

  bool _isAnonymousPost(Map<String, dynamic> post) {
    return post['isAnonymous'] == true || post['anonymous'] == true;
  }

  String _adminAuthorName(Map<String, dynamic> post) {
    return (post['authorName'] ??
            post['authorDisplayName'] ??
            post['adminUsername'] ??
            post['realUsername'] ??
            post['username'] ??
            'User')
        .toString()
        .trim();
  }

  DateTime? _parseTimestamp(dynamic ts) {
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    if (ts is num) {
      return DateTime.fromMillisecondsSinceEpoch(ts.toInt());
    }
    if (ts is String && ts.trim().isNotEmpty) {
      return DateTime.tryParse(ts.trim());
    }
    return null;
  }

  bool? _parseBoolFlag(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true') return true;
    if (normalized == 'false') return false;
    return null;
  }

  String _normalizeModerationStatus(dynamic value) {
    final normalized = (value ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (normalized.isEmpty) return '';

    if (normalized == 'approved' ||
        normalized == 'approve' ||
        normalized == 'published' ||
        normalized == 'visible') {
      return 'approved';
    }

    if (normalized == 'declined' ||
        normalized == 'rejected' ||
        normalized == 'denied') {
      return 'declined';
    }

    if (normalized == 'pending' ||
        normalized == 'review' ||
        normalized == 'under_review' ||
        normalized == 'under review' ||
        normalized.contains('pending')) {
      return 'pending';
    }

    return normalized;
  }

  String _postModerationStatus(Map<String, dynamic> post) {
    bool hasPendingSignal = false;

    for (final value in [
      post['status'],
      post['approvalStatus'],
      post['moderationStatus'],
      post['reviewStatus'],
    ]) {
      final status = _normalizeModerationStatus(value);
      if (status == 'approved' || status == 'declined') return status;
      if (status == 'pending') hasPendingSignal = true;
    }

    for (final value in [
      post['approved'],
      post['isApproved'],
      post['published'],
      post['isPublished'],
      post['visible'],
      post['isVisible'],
    ]) {
      final approved = _parseBoolFlag(value);
      if (approved == true) return 'approved';
      if (approved == false) hasPendingSignal = true;
    }

    return hasPendingSignal ? 'pending' : '';
  }

  bool _isApprovedPost(Map<String, dynamic> post) {
    final moderationStatus = _postModerationStatus(post);
    if (moderationStatus.isEmpty) {
      // Legacy posts may not have moderation fields yet.
      return true;
    }
    return moderationStatus == 'approved';
  }

  dynamic _postDateValue(Map<String, dynamic> post) {
    return post['created_at'] ??
        post['createdAt'] ??
        post['created_on'] ??
        post['createdOn'] ??
        post['timestamp'] ??
        post['date'] ??
        post['updated_at'] ??
        post['updatedAt'];
  }

  DateTime _postSortDate(Map<String, dynamic> post) {
    return _parseTimestamp(_postDateValue(post)) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  _CommentView? _commentFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required String source,
  }) {
    final data = doc.data();
    final author = (data['username'] ??
            data['author'] ??
            data['authorName'] ??
            data['name'] ??
            data['displayName'] ??
            'Anonymous')
        .toString();
    final text = (data['content'] ?? data['comment'] ?? data['text'] ?? data['message'] ?? '').toString();
    if (text.trim().isEmpty) return null;
    final authorId = (data['user_id'] ?? data['authorId'] ?? data['userId'] ?? data['uid'] ?? '').toString();
    final created = _parseTimestamp(
          data['created_at'] ??
              data['createdAt'] ??
              data['timestamp'] ??
              data['created_on'] ??
              data['time'],
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final profileBase64 = data['profileImageBase64']?.toString();
    final profileUrl = (data['profileImageUrl'] ?? data['photo_url'] ?? data['avatarUrl'])?.toString();
    final authUrl = data['authPhotoUrl']?.toString();

    return _CommentView(
      id: doc.id,
      source: source,
      author: author.isEmpty ? 'Anonymous' : author,
      authorId: authorId,
      text: text,
      createdAt: created,
      profileImageBase64: profileBase64,
      profileImageUrl: profileUrl,
      authPhotoUrl: authUrl,
    );
  }

  String _initialsFor(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  ImageProvider<Object>? _avatarForComment(_CommentView comment) {
    final direct = _buildAvatarImage(
      base64Data: comment.profileImageBase64,
      url: comment.profileImageUrl,
      fallbackUrl: comment.authPhotoUrl,
    );
    if (direct != null) return direct;

    final userId = comment.authorId;
    if (userId.isNotEmpty) {
      final cached = _userProfiles[userId];
      if (cached != null) {
        return _buildAvatarImage(
          base64Data: cached['profileImageBase64'],
          url: cached['profileImageUrl'] ?? cached['photo_url'] ?? cached['photoUrl'] ?? cached['avatarUrl'],
          fallbackUrl: cached['authPhotoUrl'] ?? cached['photo_url'] ?? cached['photoUrl'] ?? cached['avatarUrl'],
        );
      }
    }

    return null;
  }

  Future<void> _createNotification({
    required String targetUserId,
    required String title,
    required String message,
    Map<String, dynamic>? extra,
  }) async {
    if (targetUserId.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': targetUserId,
        'title': title,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        if (extra != null) ...extra,
      });
    } catch (e) {
      debugPrint('Failed to create notification: $e');
    }
  }

  Future<String?> _askReportReason({
    required String title,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var disposed = false;
    var requestedFocus = false;
    try {
      return await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) {
          if (!requestedFocus) {
            requestedFocus = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!disposed && focusNode.canRequestFocus) {
                focusNode.requestFocus();
              }
            });
          }

          final media = MediaQuery.of(ctx);
          final maxHeight =
              media.size.height - media.viewInsets.bottom - media.padding.vertical - 32;

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: maxHeight.clamp(260.0, 520.0).toDouble(),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F3FB),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF6D4BB3).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.flag_outlined,
                              color: Color(0xFF6D4BB3),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF2C2533),
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 3,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: hint,
                          hintStyle: const TextStyle(
                            color: Color(0xFF7D7487),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.all(14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFD8CFE2),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF6D4BB3),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6E8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFFD9A8)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFB75D00),
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'False or malicious reports may lead to a user violation after admin review.',
                                style: TextStyle(
                                  color: Color(0xFF7A4A00),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF6D4BB3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, controller.text.trim()),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6D4BB3),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              child: const Text('Submit'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      disposed = true;
      focusNode.dispose();
      controller.dispose();
    }
  }

  Future<void> _reportPost(Map<String, dynamic> post) async {
    final postId = (post['id'] ?? '').toString();
    if (postId.isEmpty) return;
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to report a post.')),
      );
      return;
    }

    final reason = await _askReportReason(
      title: 'Report post',
      hint: 'Tell admins what is wrong with this post.',
    );
    if (reason == null || !mounted) return;
    if (CommunityModeration.containsProfanity(reason)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CommunityModeration.messageFor('reporting'))),
      );
      return;
    }

    final reporter = _userName ?? 'User';
    final authorName = _adminAuthorName(post);
    final content = (post['content'] ?? '').toString().trim();
    final title = (post['title'] ?? '').toString().trim();
    final preview = title.isNotEmpty
        ? title
        : (content.length > 120 ? '${content.substring(0, 117)}...' : content);

    try {
      final reportRef =
          await FirebaseFirestore.instance.collection('post_reports').add({
        'postId': postId,
        'post_id': postId,
        'postOwnerId': (post['user_id'] ?? '').toString(),
        'postAuthorName': authorName,
        'postPublicName': (post['username'] ?? '').toString(),
        'postIsAnonymous': _isAnonymousPost(post),
        'postTitle': title,
        'postPreview': preview,
        'reason': reason,
        'reportedBy': _userId,
        'reportedByName': reporter,
        'reportedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        'type': 'post_report',
        'category': 'post_report',
      });

      FirebaseFirestore.instance
          .collection('community_posts')
          .doc(postId)
          .update({
        'reported': true,
        'reportCount': FieldValue.increment(1),
        'lastReportedAt': FieldValue.serverTimestamp(),
      }).catchError((_) {});

      final notifications = FirebaseFirestore.instance.collection('notifications');
      final message = reason.isNotEmpty
          ? '$reporter reported a post. Reason: $reason'
          : '$reporter reported a post.';
      final payload = {
        'title': 'Post Reported',
        'message': message,
        'postId': postId,
        'postReportId': reportRef.id,
        'reportedBy': _userId,
        'reportedByName': reporter,
        'postAuthorName': authorName,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'post_report',
        'category': 'post_report',
      };
      await Future.wait([
        notifications.add({...payload, 'targetRole': 'web-admin-bfar'}),
        notifications.add({...payload, 'targetRole': 'web-admin-pcg'}),
      ]);

      if (!mounted) return;
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Report sent'),
          content: const Text('This post has been reported to the admins.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Report post failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to report post: $e')),
        );
      }
    }
  }

  Future<void> _reportComment({
    required String postId,
    required _CommentView comment,
  }) async {
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to report a comment.')),
      );
      return;
    }

    final reason = await _askReportReason(
      title: 'Report comment',
      hint: 'Tell admins what is wrong with this comment.',
    );
    if (reason == null || !mounted) return;
    if (CommunityModeration.containsProfanity(reason)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(CommunityModeration.messageFor('reporting'))),
      );
      return;
    }

    final reporterName = _userName ?? 'User';
    try {
      final reportRef =
          await FirebaseFirestore.instance.collection('comment_reports').add({
        'post_id': postId,
        'postId': postId,
        'comment_id': comment.id,
        'commentId': comment.id,
        'commentSource': comment.source,
        'comment_text': comment.text,
        'commentText': comment.text,
        'comment_author_id': comment.authorId,
        'commentAuthorId': comment.authorId,
        'commentAuthorName': comment.author,
        'reported_by': _userId,
        'reportedBy': _userId,
        'reportedByName': reporterName,
        'reported_at': FieldValue.serverTimestamp(),
        'reportedAt': FieldValue.serverTimestamp(),
        'reason': reason,
        'status': 'pending',
        'type': 'comment_report',
        'category': 'comment_report',
      });

      final baseNotification = {
        'title': 'Comment Reported',
        'message': reason.isNotEmpty
            ? '$reporterName reported a comment. Reason: $reason'
            : '$reporterName reported a comment: "${comment.text}"',
        'postId': postId,
        'commentId': comment.id,
        'commentReportId': reportRef.id,
        'reportedBy': _userId,
        'reportedByName': reporterName,
        'commentAuthorId': comment.authorId,
        'commentAuthorName': comment.author,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': 'comment_report',
        'category': 'comment_report',
      };

      final notifications = FirebaseFirestore.instance.collection('notifications');
      await Future.wait([
        notifications.add({
          ...baseNotification,
          'targetRole': 'web-admin-bfar',
        }),
        notifications.add({
          ...baseNotification,
          'targetRole': 'web-admin-pcg',
        }),
      ]);

      if (!mounted) return;
      showDialog(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          title: const Text('Report sent'),
          content: const Text('Your report has been sent to admin for review.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Report comment failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to report comment: $e')),
        );
      }
    }
  }

  Future<void> _notifyPcgPosts(List<Map<String, dynamic>> posts) async {
    if (_userId == null) return;

    for (final post in posts) {
      final cat = (post['effectiveCategory'] ?? post['category'] ?? '').toString().toLowerCase();
      final role = (post['role'] ?? post['userRole'] ?? post['createdByRole'] ?? '').toString().toLowerCase();
      final authorId = (post['user_id'] ?? '').toString();
      final postId = (post['id'] ?? '').toString();

      if (postId.isEmpty) continue;
      if (authorId.isNotEmpty && authorId == _userId) continue;
      if (!_isApprovedPost(post)) continue;

      final bool isPcgPost = cat.contains('pcg') || role.contains('pcg');
      final bool isBfarPost = cat.contains('bfar') || role.contains('bfar');
      final bool isAdminPost = isPcgPost || isBfarPost || cat.contains('admin') || role.contains('admin') || role.contains('web-admin');
      if (!isAdminPost) continue;

      final notifiedUsers = post['notifiedUsers'] is List
          ? List<String>.from(post['notifiedUsers'] as List)
          : <String>[];
      if (notifiedUsers.contains(_userId)) continue;
      if (!_scheduledAdminPostNotifications.add(postId)) continue;

      final postTitle = (post['title'] ?? '').toString().trim();
      final postContent = (post['content'] ?? '').toString().trim();
      final defaultMessage = isPcgPost
          ? 'New PCG post published.'
          : isBfarPost
              ? 'New BFAR post published.'
              : 'New admin post published.';
      final message = postTitle.isNotEmpty ? postTitle : (postContent.isNotEmpty ? postContent : defaultMessage);

      final bool usePcgPayload = isPcgPost;
      final bool useBfarPayload = !isPcgPost && isBfarPost; // prefer PCG tag when both match

      final payload = <String, dynamic>{
        'targetUserId': _userId,
        'title': usePcgPayload
            ? 'PCG Web Update'
            : useBfarPayload
                ? 'BFAR Web Update'
                : 'Admin Post',
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'type': usePcgPayload
            ? 'pcg_post'
            : useBfarPayload
                ? 'bfar_post'
                : 'admin_post',
        'category': usePcgPayload
            ? 'pcg'
            : useBfarPayload
                ? 'bfar'
                : 'admin',
        'adminPostId': postId,
      };
      if (usePcgPayload) {
        payload['pcgPostId'] = postId;
      }
      if (useBfarPayload) {
        payload['bfarPostId'] = postId;
      }

      try {
        await FirebaseFirestore.instance.collection('notifications').add(payload);

        FirebaseFirestore.instance.collection('community_posts').doc(postId).update({
          'notifiedUsers': FieldValue.arrayUnion([_userId]),
        }).catchError((_) {});
      } catch (e) {
        _scheduledAdminPostNotifications.remove(postId);
        debugPrint('Admin post notification failed: $e');
      }
    }
  }

  Future<void> _notifyOwnPostStatuses(List<Map<String, dynamic>> posts) async {
    if (_userId == null) return;

    for (final post in posts) {
      final postId = (post['id'] ?? '').toString();
      if (postId.isEmpty) continue;
      if (post['user_id'] != _userId) continue;

      final status = _postModerationStatus(post);
      final notified = post['statusNotified'] == true;
      if (status != 'approved' && status != 'declined') continue;
      if (notified) continue;
      if (!_scheduledPostStatusNotifications.add(postId)) continue;

      final title = status == 'approved' ? 'Post Approved' : 'Post Declined';
      final message = status == 'approved'
          ? 'Your post has been approved and is now visible.'
          : 'Your post was declined by an admin.';

      try {
        await _createNotification(
          targetUserId: _userId!,
          title: title,
          message: message,
        );
        await FirebaseFirestore.instance
            .collection('community_posts')
            .doc(postId)
            .update({'statusNotified': true});
      } catch (e) {
        _scheduledPostStatusNotifications.remove(postId);
        debugPrint('Post status notification failed: $e');
      }
    }
  }

  void _scheduleFeedSideEffects(List<Map<String, dynamic>> posts) {
    if (_userId == null || posts.isEmpty) return;
    final snapshotPosts =
        posts.map((post) => Map<String, dynamic>.from(post)).toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifyPcgPosts(snapshotPosts);
      _notifyOwnPostStatuses(snapshotPosts);
    });
  }

  ImageProvider<Object>? _buildAvatarImage({
    String? base64Data,
    String? url,
    String? fallbackUrl,
  }) {
    try {
      if (base64Data != null) {
        return MemoryImage(base64Decode(base64Data));
      }
    } catch (_) {}
    if (url != null) return NetworkImage(url);
    if (fallbackUrl != null) return NetworkImage(fallbackUrl);
    return null;
  }

  @override
  void initState() {
    super.initState();
    _initialPostId = widget.initialPostId;
    if (_initialPostId != null && _initialPostId!.isNotEmpty) {
      _singlePostStream = FirebaseFirestore.instance
          .collection('community_posts')
          .doc(_initialPostId)
          .snapshots();
    }
    _loadUser();
  }

  @override
  void dispose() {
    for (final sub in _profileListeners.values) {
      sub.cancel();
    }
    _profileListeners.clear();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _userId = user.uid;
      _authPhotoUrl = user.photoURL;
    });

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        final data = doc.data();
        _profileImageBase64 = data?['profileImageBase64'];
        _profileImageUrl = data?['profileImageUrl'];
        _userRole = (data?['role'] ?? data?['category'] ?? '').toString();
        _userName = data?['fullName'] ??
            data?['name'] ??
            "${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}".trim();
      }
      _userName ??= user.displayName ?? user.email?.split('@').first ?? 'User';
    } catch (e) {
      debugPrint("Error loading profile image: $e");
    }
  }

  Future<List<dynamic>> fetchApprovedPosts() async {
    return [];
  }

  Future<void> _onRefresh() async {
    await _loadUser();
    setState(() {
      postsStream = FirebaseFirestore.instance
          .collection('community_posts')
          .snapshots();
    });
    await Future.delayed(const Duration(milliseconds: 250));
  }

  void _subscribeToUserProfile(String userId) {
    if (userId.isEmpty) return;
    if (_profileListeners.containsKey(userId)) return;

    final sub = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((doc) {
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      _userProfiles[userId] = {
        'profileImageBase64': data['profileImageBase64']?.toString(),
        'profileImageUrl': data['profileImageUrl']?.toString(),
        'authPhotoUrl': data['authPhotoUrl']?.toString(),
        'photo_url': data['photo_url']?.toString(),
        'photoUrl': data['photoUrl']?.toString(),
        'avatarUrl': data['avatarUrl']?.toString(),
        'role': data['role']?.toString(),
        'roleLabel': data['roleLabel']?.toString(),
        'category': data['category']?.toString(),
      };
      if (mounted) setState(() {});
    }, onError: (e) {
      debugPrint('Failed to listen to profile $userId: $e');
    });

    _profileListeners[userId] = sub;
  }

  String _formatDate(dynamic value) {
    try {
      if (value is Timestamp) {
        return DateFormat('MMM d, yyyy h:mm a').format(value.toDate());
      }
      if (value is String && value.isNotEmpty) {
        return DateFormat('MMM d, yyyy h:mm a').format(DateTime.parse(value));
      }
      if (value is DateTime) {
        return DateFormat('MMM d, yyyy h:mm a').format(value);
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  ImageProvider<Object>? _resolveImageProvider(String image) {
    if (image.isEmpty) return null;
    try {
      if (image.startsWith('data:image')) {
        final base64Part = image.split(',').last;
        final bytes = base64Decode(base64Part);
        return MemoryImage(bytes);
      }
    } catch (_) {}

    if (image.startsWith('http')) return NetworkImage(image);
    return null;
  }

  Widget? _buildPostImage(
    String image, {
    required String heroTag,
    required List<String> allImages,
    required int index,
  }) {
    final provider = _resolveImageProvider(image);
    if (provider == null) return null;
    return GestureDetector(
      onTap: () => _openImageViewer(allImages, index, heroTag: heroTag),
      child: Hero(
        tag: heroTag.isEmpty ? 'post-image-${image.hashCode}' : heroTag,
        child: Container(
          color: Colors.black12,
          child: Image(
            image: provider,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }

  List<String> _normalizeImages(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e == null ? '' : e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw == null) return [];
    final str = raw.toString().trim();
    return str.isEmpty ? [] : [str];
  }

  Widget? _buildPostMedia({
    required String postId,
    required dynamic rawImages,
  }) {
    final images = _normalizeImages(rawImages);
    if (images.isEmpty) return null;
    if (images.length == 1) {
      final single = _buildPostImage(
        images.first,
        heroTag: 'post-image-${postId.isNotEmpty ? postId : images.first.hashCode}',
        allImages: images,
        index: 0,
      );
      if (single == null) return null;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.of(context).size.width;
          final aspectRatio = width < 380 ? 4 / 3 : 16 / 10;

          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: single,
            ),
          );
        },
      );
    }
    final clampedImages = images.take(4).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final rows = (clampedImages.length / 2).ceil().clamp(1, 2).toInt();
        final targetHeight = (availableWidth * (rows == 1 ? 0.5 : 0.9))
            .clamp(rows == 1 ? 150.0 : 260.0, rows == 1 ? 280.0 : 520.0)
            .toDouble();
        final tileWidth = (availableWidth - spacing) / 2;
        final tileHeight = (targetHeight - ((rows - 1) * spacing)) / rows;
        final aspectRatio = tileWidth / tileHeight;

        return SizedBox(
          height: targetHeight,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: clampedImages.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              childAspectRatio: aspectRatio,
            ),
            itemBuilder: (context, index) {
              final img = clampedImages[index];
              final child = _buildPostImage(
                img,
                heroTag: 'post-image-$postId-$index',
                allImages: clampedImages,
                index: index,
              );
              if (child == null) return const SizedBox.shrink();
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: child,
              );
            },
          ),
        );
      },
    );
  }

  void _openImageViewer(List<String> images, int initialIndex, {String? heroTag}) {
    final providers = images
        .map((img) => _resolveImageProvider(img))
        .whereType<ImageProvider<Object>>()
        .toList();
    if (providers.isEmpty) return;

    final controller = PageController(initialPage: initialIndex.clamp(0, providers.length - 1));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (viewerContext) {
          return Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              elevation: 0,
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: PageView.builder(
              controller: controller,
              itemCount: providers.length,
              itemBuilder: (context, index) {
                final useHero = heroTag != null && index == controller.initialPage;
                final imageWidget = InteractiveViewer(
                  minScale: 0.9,
                  maxScale: 4.0,
                  child: Image(
                    image: providers[index],
                    fit: BoxFit.contain,
                  ),
                );
                if (useHero) {
                  return Center(
                    child: Hero(
                      tag: heroTag,
                      child: imageWidget,
                    ),
                  );
                }
                return Center(child: imageWidget);
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _toggleLike(
    String postDocId, {
    required String ownerId,
    required String ownerName,
    String? postTitle,
    required bool currentlyLiked,
  }) async {
    void updateUi(VoidCallback fn) {
      if (mounted) setState(fn);
    }

    if (_userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to like posts.')),
        );
      }
      return;
    }

    final oldCount = likeCounts[postDocId] ?? 0;
    final newValue = !currentlyLiked;
    final optimisticCount = max(0, oldCount + (newValue ? 1 : -1));
    updateUi(() {
      likedPosts[postDocId] = newValue;
      likeCounts[postDocId] = optimisticCount;
    });

    try {
      int finalCount = optimisticCount;
      await FirebaseFirestore.instance.runTransaction((txn) async {
        final ref = FirebaseFirestore.instance.collection('community_posts').doc(postDocId);
        final snap = await txn.get(ref);
        final data = snap.data() ?? {};
        final List likedBy = (data['likedBy'] as List?) ?? <String>[];
        final bool alreadyLiked = likedBy.contains(_userId);
        int currentCount;
        if (data['likes_count'] is num) {
          currentCount = (data['likes_count'] as num).toInt();
        } else {
          currentCount = likedBy.length;
        }

        if (newValue && !alreadyLiked) {
          finalCount = currentCount + 1;
          txn.update(ref, {
            'likedBy': FieldValue.arrayUnion([_userId]),
            'likes_count': finalCount,
          });
        } else if (!newValue && alreadyLiked) {
          finalCount = max(0, currentCount - 1);
          txn.update(ref, {
            'likedBy': FieldValue.arrayRemove([_userId]),
            'likes_count': finalCount,
          });
        } else {
          finalCount = currentCount;
        }
      });

      updateUi(() {
        likedPosts[postDocId] = newValue;
        likeCounts[postDocId] = finalCount;
      });

      final currentUser = _auth.currentUser;
      if (newValue && ownerId.isNotEmpty && currentUser != null && ownerId != currentUser.uid) {
        final likerName = _userName ?? currentUser.displayName ?? 'Someone';
        final titleText = (postTitle ?? '').trim();
        final message = titleText.isNotEmpty
            ? '$likerName liked your post "$titleText".'
            : '$likerName liked your post.';
        await _createNotification(
          targetUserId: ownerId,
          title: 'New Like',
          message: message,
          extra: {
            'type': 'post_like',
            'postId': postDocId,
            'actorName': likerName,
          },
        );
      }
    } catch (e) {
      debugPrint('Failed to update like: $e');
      updateUi(() {
        likedPosts[postDocId] = currentlyLiked;
        likeCounts[postDocId] = oldCount;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update like. Please try again.')),
        );
      }
    }
  }

  void _showCommentDialog(
    String postIdStr, {
    required String postOwnerId,
    required String postOwnerName,
    String? postTitle,
  }) {
    final TextEditingController commentController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final keyboardHeight = media.viewInsets.bottom;
        final horizontalPadding = Responsive.value<double>(
          sheetContext,
          mobile: 12,
          tablet: 20,
        );
        final availableHeight = max(
          260.0,
          media.size.height - keyboardHeight - media.padding.top - media.padding.bottom - 20,
        );
        final targetHeight = media.size.height * (keyboardHeight > 0 ? 0.78 : 0.68);
        final sheetHeight = min(availableHeight, max(320.0, targetHeight));

        return Padding(
          padding: EdgeInsets.only(
            bottom: keyboardHeight + 12,
            left: horizontalPadding,
            right: horizontalPadding,
            top: 12,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SizedBox(
                height: sheetHeight,
            child: Column(
              children: [
                Container(
                  width: 50,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  "Comments",
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('community_posts')
                        .doc(postIdStr)
                        .collection('comments')
                        .snapshots(),
                    builder: (context, subSnap) {
                      return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('comments')
                        .where('postId', isEqualTo: postIdStr)
                        .snapshots(),
                        builder: (context, adminSnap) {
                          if (subSnap.connectionState == ConnectionState.waiting ||
                              adminSnap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final combined = <_CommentView>[];
                          for (final doc in subSnap.data?.docs ?? []) {
                            final mapped = _commentFromDoc(doc, source: 'sub');
                            if (mapped != null) combined.add(mapped);
                          }
                          for (final doc in adminSnap.data?.docs ?? []) {
                            final mapped = _commentFromDoc(doc, source: 'root');
                            if (mapped != null) combined.add(mapped);
                          }

                          _scheduleProfileSubscriptions(
                            combined.map((comment) => comment.authorId),
                          );

                          combined.sort((a, b) {
                            final ta = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            final tb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
                            return tb.compareTo(ta);
                          });

                          if (combined.isEmpty) {
                            return const Center(child: Text("No comments yet"));
                          }

                          return ListView.separated(
                            itemCount: combined.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final comment = combined[i];
                              final time = comment.createdAt != null
                                  ? DateFormat('MMM dd, yyyy').format(comment.createdAt!)
                                  : '';
                              final canEdit = comment.source == 'sub' && comment.authorId == _userId;
                              final initial = _initialsFor(comment.author);

                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  dense: false,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.indigo.shade50,
                                    foregroundColor: Colors.indigo.shade900,
                                    backgroundImage: _avatarForComment(comment),
                                    child: _avatarForComment(comment) == null
                                        ? Text(initial, style: const TextStyle(fontWeight: FontWeight.w700))
                                        : null,
                                  ),
                                  title: Text(
                                    comment.author,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 2),
                                      Text(
                                        comment.text,
                                        style: const TextStyle(fontSize: 13, height: 1.3),
                                      ),
                                      if (time.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            time,
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: IconButton(
                                    tooltip: canEdit ? 'Comment actions' : 'Report comment',
                                    icon: Icon(
                                      canEdit
                                          ? Icons.more_horiz
                                          : Icons.flag_outlined,
                                      color: canEdit
                                          ? Colors.black54
                                          : Colors.redAccent,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      if (canEdit) {
                                        _showCommentActions(
                                          context,
                                          postIdStr: postIdStr,
                                          commentId: comment.id,
                                          currentText: comment.text,
                                        );
                                        return;
                                      }

                                      Navigator.pop(context);
                                      Future<void>.delayed(
                                        const Duration(milliseconds: 180),
                                        () {
                                          if (!mounted) return;
                                          _reportComment(
                                            postId: postIdStr,
                                            comment: comment,
                                          );
                                        },
                                      );
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentController,
                        decoration: InputDecoration(
                          hintText: "Add a comment",
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.indigo.shade300),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                          onPressed: () async {
                            final text = commentController.text.trim();
                            if (text.isEmpty) return;
                            if (CommunityModeration.containsProfanity(text)) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    CommunityModeration.messageFor(
                                      'commenting',
                                    ),
                                  ),
                                ),
                              );
                              return;
                            }
                            final userName = _userName ?? 'User';
                            await FirebaseFirestore.instance
                                .collection('community_posts')
                                .doc(postIdStr)
                                .collection('comments')
                                .add({
                              'content': text,
                              'user_id': _userId,
                              'username': userName,
                              'created_at': FieldValue.serverTimestamp(),
                              'post_id': postIdStr,
                              'postId': postIdStr,
                              if (_profileImageBase64 != null) 'profileImageBase64': _profileImageBase64,
                              if (_profileImageUrl != null) 'profileImageUrl': _profileImageUrl,
                              if (_authPhotoUrl != null) 'authPhotoUrl': _authPhotoUrl,
                            });
                            await FirebaseFirestore.instance
                                .collection('community_posts')
                                .doc(postIdStr)
                                .update({'comments_count': FieldValue.increment(1)});
                            setState(() {
                              commentCounts[postIdStr] = (commentCounts[postIdStr] ?? 0) + 1;
                            });
                            final currentUser = _auth.currentUser;
                            if (currentUser != null &&
                                postOwnerId.isNotEmpty &&
                                postOwnerId != currentUser.uid) {
                              final titleText = (postTitle ?? '').trim();
                              final message = titleText.isNotEmpty
                                  ? '$userName commented on your post "$titleText": "$text"'
                                  : '$userName commented on your post: "$text"';
                              await _createNotification(
                                targetUserId: postOwnerId,
                                title: 'New Comment',
                                message: message,
                                extra: {
                                  'type': 'post_comment',
                                  'postId': postIdStr,
                                  'actorName': userName,
                                  'comment': text,
                                },
                              );
                            }
                            commentController.clear();
                          },
                          child: const Text("Post"),
                        ),
                      ],
                ),
              ],
            ),
          ),
            ),
          ),
        );
      },
    );
  }

  ImageProvider<Object>? _avatarForPost(Map<String, dynamic> post) {
    if (_isAnonymousPost(post)) return null;

    final avatar = _buildAvatarImage(
      base64Data: post['profileImageBase64'] ?? post['adminProfileImageBase64'],
      url: post['profileImageUrl'] ?? post['adminProfileImageUrl'],
      fallbackUrl: post['authPhotoUrl'] ?? post['adminAuthPhotoUrl'],
    );
    if (avatar != null) return avatar;

    final userId = (post['user_id'] ?? '').toString();
    if (userId.isNotEmpty) {
      final cached = _userProfiles[userId];
      if (cached != null) {
        return _buildAvatarImage(
          base64Data: cached['profileImageBase64'],
          url: cached['profileImageUrl'],
          fallbackUrl: cached['authPhotoUrl'],
        );
      }
    }
    return null;
  }

  void _scheduleProfileSubscriptions(Iterable<String> userIds) {
    final pending = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !_userProfiles.containsKey(id))
        .where(_scheduledProfileSubscriptions.add)
        .toList();

    if (pending.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final id in pending) {
        _subscribeToUserProfile(id);
      }
    });
  }

  Widget _buildComposerRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final avatarRadius = compact ? 18.0 : 21.0;
        final actionSize = compact ? 38.0 : 42.0;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF4F9FF)],
            ),
            border: Border.all(color: const Color(0xFFD8E4F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA7C3).withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfilePage()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFBFD2E9), width: 1.6),
                  ),
                  child: CircleAvatar(
                    radius: avatarRadius,
                    backgroundColor: const Color(0xFFEAF1FF),
                    backgroundImage: _buildAvatarImage(
                      base64Data: _profileImageBase64,
                      url: _profileImageUrl,
                      fallbackUrl: _authPhotoUrl,
                    ),
                    child: (_profileImageBase64 == null &&
                            _profileImageUrl == null &&
                            _authPhotoUrl == null)
                        ? Icon(Icons.person, size: compact ? 19 : 21, color: _ink)
                        : null,
                  ),
                ),
              ),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                    );
                  },
                  child: Ink(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 12 : 14,
                      vertical: compact ? 11 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "What's on your mind?",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _subtleInk,
                        fontWeight: FontWeight.w600,
                        fontSize: compact ? 13 : 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreatePostScreen()),
                  );
                },
                child: Ink(
                  width: actionSize,
                  height: actionSize,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8F3DD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFBEE7C8)),
                  ),
                  child: Icon(
                    Icons.add_photo_alternate_rounded,
                    size: compact ? 20 : 22,
                    color: const Color(0xFF1A7F3D),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryChips() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return SizedBox(
          height: compact ? 40 : 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            separatorBuilder: (_, __) => SizedBox(width: compact ? 6 : 8),
            itemBuilder: (context, index) {
              final cat = categories[index];
              final selected = selectedCategory == cat;
              return ChoiceChip(
                label: Text(cat, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: selected,
                onSelected: (_) => setState(() => selectedCategory = cat),
                showCheckmark: false,
                backgroundColor: const Color(0xFFEAF1FF),
                selectedColor: const Color(0xFF124F8A),
                side: BorderSide(
                  color: selected ? Colors.transparent : const Color(0xFFD0DEEE),
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.white : _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 12 : 12.8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFeedStateCard(String text, {bool loading = false}) {
    return Center(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8E4F0)),
        ),
        child: loading
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Loading posts...',
                    style: TextStyle(
                      color: _subtleInk,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            : Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _subtleInk,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final singlePostMode = _initialPostId != null && _initialPostId!.isNotEmpty;
    if (singlePostMode) {
      final horizontalPadding = Responsive.pagePadding(context);
      final verticalPadding = Responsive.verticalSpace(context);
      final contentMaxWidth = Responsive.maxContentWidth(context, maxWidth: _feedMaxWidth);
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: Colors.black,
          centerTitle: false,
          title: const Text("Community Post", style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: _buildSinglePostView(
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding,
              ),
            ),
          ),
        ),
      );
    }

    final horizontalPadding = Responsive.pagePadding(context);
    final verticalPadding = Responsive.verticalSpace(context);
    final contentMaxWidth = Responsive.maxContentWidth(context, maxWidth: _feedMaxWidth);
    final stateHeight = max(180.0, MediaQuery.of(context).size.height * 0.28);
    final titleFontSize = Responsive.value<double>(
      context,
      mobile: Responsive.isSmall(context) ? 26 : 30,
      tablet: 32,
    );
    return Scaffold(
      backgroundColor: _pageBottom,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        foregroundColor: _ink,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Text(
          "Community",
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: titleFontSize,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_pageTop, _pageBottom],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildComposerRow(),
                    const SizedBox(height: 10),
                    _buildCategoryChips(),
                    SizedBox(height: max(8, verticalPadding - 6)),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: postsStream,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: stateHeight,
                                    child: _buildFeedStateCard(
                                      'Loading posts...',
                                      loading: true,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: stateHeight,
                                    child: _buildFeedStateCard(
                                      "Error: ${snapshot.error}",
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          final docs = snapshot.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: stateHeight,
                                    child: _buildFeedStateCard('No posts yet'),
                                  ),
                                ],
                              ),
                            );
                          }

                          final posts = docs
                              .map((doc) => {'id': doc.id, ...doc.data()})
                              .toList()
                            ..sort(
                              (a, b) =>
                                  _postSortDate(b).compareTo(_postSortDate(a)),
                            );

                          final postsWithEffectiveCategory = posts.map((post) {
                            final isMine = post['user_id'] == _userId;
                            final rawRole = isMine &&
                                    _userRole != null &&
                                    _userRole!.isNotEmpty
                                ? _userRole
                                : (post['category'] ??
                                    post['role'] ??
                                    post['userRole'] ??
                                    post['createdByRole']);
                            final effectiveCategory = rawRole;
                            return {...post, 'effectiveCategory': effectiveCategory};
                          }).toList();

                          _scheduleProfileSubscriptions(
                            postsWithEffectiveCategory
                                .map((post) => (post['user_id'] ?? '').toString()),
                          );
                          _scheduleFeedSideEffects(postsWithEffectiveCategory);

                          final filteredPosts = selectedCategory == "All"
                              ? postsWithEffectiveCategory
                                  .where(_isApprovedPost)
                                  .toList()
                              : selectedCategory == "My Posts"
                                  ? postsWithEffectiveCategory
                                      .where(
                                        (post) =>
                                            post['user_id'] == _userId &&
                                            _isApprovedPost(post),
                                      )
                                      .toList()
                                  : postsWithEffectiveCategory.where((post) {
                                      final authorProfile = _userProfiles[
                                          (post['user_id'] ?? '').toString()];
                                      final combinedRole = (post[
                                                  'effectiveCategory'] ??
                                              post['category'] ??
                                              post['role'] ??
                                              post['userRole'] ??
                                              post['createdByRole'] ??
                                              authorProfile?['role'] ??
                                              authorProfile?['roleLabel'] ??
                                              authorProfile?['category'] ??
                                              '')
                                          .toString();
                                      final bucket = _roleBucket(combinedRole);
                                      if (selectedCategory == "Fisherman") {
                                        return bucket == 'fisherman' &&
                                            _isApprovedPost(post);
                                      }
                                      if (selectedCategory == "Resident") {
                                        return bucket == 'resident' &&
                                            _isApprovedPost(post);
                                      }
                                      if (selectedCategory == "BFAR") {
                                        return bucket == 'bfar' &&
                                            _isApprovedPost(post);
                                      }
                                      if (selectedCategory == "PCG") {
                                        return bucket == 'pcg' &&
                                            _isApprovedPost(post);
                                      }
                                      return bucket ==
                                              selectedCategory.toLowerCase() &&
                                          _isApprovedPost(post);
                                    }).toList();

                          if (filteredPosts.isEmpty) {
                            return _buildFeedStateCard(
                              "No posts found for this category.",
                            );
                          }

                          for (final post in filteredPosts) {
                            final postId = (post['id'] ?? '').toString();
                            final likedBy =
                                (post['likedBy'] as List?) ?? <dynamic>[];
                            likeCounts.putIfAbsent(
                              postId,
                              () => post['likes_count'] is num
                                  ? (post['likes_count'] as num).toInt()
                                  : likedBy.length,
                            );
                            commentCounts.putIfAbsent(
                              postId,
                              () => post['comments_count'] ?? 0,
                            );
                          }

                          return RefreshIndicator(
                            onRefresh: _onRefresh,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(bottom: verticalPadding),
                              itemCount: filteredPosts.length,
                              itemBuilder: (context, i) {
                                final post = filteredPosts[i];
                                return _buildPostCard(
                                  post,
                                  key: ValueKey(post['id'] ?? i),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() => _selectedIndex = index);
        },
      ),
    );
  }

  void _showPostActions(
    BuildContext context,
    Map<String, dynamic> post, {
    required bool isMine,
  }) {
    final postId = (post['id'] ?? '').toString();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              if (isMine)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  title: const Text('Delete Post'),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await FirebaseFirestore.instance.collection('community_posts').doc(postId).delete();
                      setState(() {
                        likeCounts.remove(postId);
                        commentCounts.remove(postId);
                        likedPosts.remove(postId);
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Post deleted.")),
                      );
                    } catch (e) {
                      debugPrint("Delete failed: $e");
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Failed to delete post: $e")),
                        );
                      }
                    }
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.flag_outlined, color: Colors.redAccent),
                  title: const Text('Report Post'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Future<void>.delayed(
                      const Duration(milliseconds: 180),
                      () {
                        if (!mounted) return;
                        _reportPost(post);
                      },
                    );
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showCommentActions(BuildContext context,
      {required String postIdStr, required String commentId, required String currentText}) {
    final editController = TextEditingController(text: currentText);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 50,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Comment'),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) {
                      return AlertDialog(
                        title: const Text('Edit Comment'),
                        content: TextField(
                          controller: editController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'Update your comment',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final newText = editController.text.trim();
                              if (newText.isEmpty) return;
                              if (CommunityModeration.containsProfanity(newText)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      CommunityModeration.messageFor(
                                        'saving',
                                      ),
                                    ),
                                  ),
                                );
                                return;
                              }
                              try {
                                await FirebaseFirestore.instance
                                    .collection('community_posts')
                                    .doc(postIdStr)
                                    .collection('comments')
                                    .doc(commentId)
                                    .update({'content': newText, 'updated_at': FieldValue.serverTimestamp()});
                                if (mounted) Navigator.pop(ctx);
                              } catch (e) {
                                debugPrint('Edit comment failed: $e');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Failed to update comment: $e')),
                                  );
                                }
                              }
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Comment'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await FirebaseFirestore.instance
                        .collection('community_posts')
                        .doc(postIdStr)
                        .collection('comments')
                        .doc(commentId)
                        .delete();
                    await FirebaseFirestore.instance
                        .collection('community_posts')
                        .doc(postIdStr)
                        .update({'comments_count': FieldValue.increment(-1)});
                    setState(() {
                      commentCounts[postIdStr] = (commentCounts[postIdStr] ?? 0) - 1;
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Comment deleted.')),
                      );
                    }
                  } catch (e) {
                    debugPrint('Delete comment failed: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to delete comment: $e')),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    final pending = status == 'pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pending ? const Color(0xFFFFF4E6) : const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: pending ? const Color(0xFFFBD38D) : const Color(0xFFFCA5A5),
        ),
      ),
      child: Text(
        pending ? 'Pending' : 'Declined',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: pending ? const Color(0xFF975A16) : const Color(0xFF9B1C1C),
          fontSize: 10.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildFooterAction({
    required IconData icon,
    required String count,
    required VoidCallback onTap,
    required Color iconColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: iconColor),
            const SizedBox(width: 5),
            Text(
              count,
              style: const TextStyle(
                fontSize: 12.6,
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateChip(String date) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        date,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.4,
          color: _subtleInk,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPostFooter({
    required String postId,
    required String ownerId,
    required String ownerName,
    required String postTitle,
    required bool isLiked,
    required String date,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFooterAction(
              icon: isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              iconColor: isLiked ? const Color(0xFFDC2626) : _ink,
              count: '${likeCounts[postId] ?? 0}',
              onTap: () => _toggleLike(
                postId,
                ownerId: ownerId,
                ownerName: ownerName,
                postTitle: postTitle,
                currentlyLiked: isLiked,
              ),
            ),
            const SizedBox(width: 8),
            _buildFooterAction(
              icon: Icons.mode_comment_outlined,
              iconColor: _ink,
              count: '${commentCounts[postId] ?? 0}',
              onTap: () => _showCommentDialog(
                postId,
                postOwnerId: ownerId,
                postOwnerName: ownerName,
                postTitle: postTitle,
              ),
            ),
          ],
        );

        if (date.isEmpty) return actions;
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              actions,
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: _buildDateChip(date),
              ),
            ],
          );
        }

        return Row(
          children: [
            actions,
            const SizedBox(width: 8),
            const Spacer(),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildDateChip(date),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPostCard(dynamic post, {Key? key}) {
        final postMap = Map<String, dynamic>.from(post as Map);
        final postId = (postMap['id'] ?? '').toString();
        final isMine = postMap['user_id'] == _userId;
        final isAnonymous = _isAnonymousPost(postMap);
        final canSeeAnonymousIdentity = _canSeeAnonymousIdentity();
        final ImageProvider<Object>? avatar = isAnonymous
            ? null
            : (isMine
                ? _buildAvatarImage(
                    base64Data: _profileImageBase64,
                    url: _profileImageUrl,
                    fallbackUrl: _authPhotoUrl,
                  )
                : _avatarForPost(postMap));
        final publicName = (postMap['username'] ?? 'Anonymous').toString();
        final adminName = _adminAuthorName(postMap);
        final adminAnonymousLabel =
            adminName.toLowerCase() == 'anonymous' || adminName.isEmpty
                ? 'Anonymous'
                : 'Anonymous ($adminName)';
        final name = isAnonymous
            ? (canSeeAnonymousIdentity
                  ? adminAnonymousLabel
                  : isMine
                      ? 'Anonymous (You)'
                      : 'Anonymous')
            : isMine
                ? (_userName ?? publicName)
                : publicName;
        final authorProfile = _userProfiles[(postMap['user_id'] ?? '').toString()];
        final rawRole = (postMap['effectiveCategory'] ??
                postMap['category'] ??
                postMap['role'] ??
                postMap['userRole'] ??
                postMap['createdByRole'] ??
                authorProfile?['role'] ??
                authorProfile?['roleLabel'] ??
                authorProfile?['category'] ??
                '')
            .toString();
        final role = _roleLabel(rawRole);
        final rawTitle = (postMap['title'] ?? '').toString().trim();
        final title = rawTitle.toLowerCase() == 'user post' ? '' : rawTitle;
        final content = (postMap['content'] ?? '').toString();
        final image = (postMap['image'] ?? '').toString();
        final date = _formatDate(_postDateValue(postMap));
        final status = _postModerationStatus(postMap);
        final List likedBy = (postMap['likedBy'] as List?) ?? <String>[];
        final bool isLiked = likedPosts[postId] ?? likedBy.contains(_userId);
        likedPosts[postId] = isLiked;
        final compact = MediaQuery.of(context).size.width < 360;

        final mediaWidget = _buildPostMedia(
          postId: postId.isNotEmpty ? postId : image.hashCode.toString(),
          rawImages: postMap['images'] ?? postMap['image'],
        );

        return Container(
          key: key,
          margin: EdgeInsets.only(bottom: compact ? 12 : 14),
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 12,
            compact ? 10 : 12,
            compact ? 10 : 12,
            compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 18 : 22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF6FAFF)],
            ),
            border: Border.all(color: const Color(0xFFD8E4F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8DA7C3).withValues(alpha: 0.14),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFBFD2E9), width: 1.5),
                    ),
                    child: CircleAvatar(
                      radius: compact ? 17 : 18,
                      backgroundColor: const Color(0xFFEAF1FF),
                      backgroundImage: avatar,
                      child: avatar == null
                          ? const Icon(Icons.person, size: 18, color: _ink)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                role,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.4,
                                  color: _subtleInk,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isMine &&
                                status.isNotEmpty &&
                                status != 'approved') ...[
                              const SizedBox(width: 6),
                              Flexible(child: _buildStatusBadge(status)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _showPostActions(
                      context,
                      postMap,
                      isMine: isMine,
                    ),
                    child: Ink(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.more_horiz, color: _subtleInk, size: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (title.isNotEmpty)
                Text(
                  title,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 16.4,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              if (title.isNotEmpty) const SizedBox(height: 8),
              if (mediaWidget != null) mediaWidget,
              if (mediaWidget != null) const SizedBox(height: 10),
              if (content.isNotEmpty)
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14.2,
                    color: _subtleInk,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              const SizedBox(height: 12),
              _buildPostFooter(
                postId: postId,
                ownerId: (postMap['user_id'] ?? '').toString(),
                ownerName: name,
                postTitle: title,
                isLiked: isLiked,
                date: date,
              ),
            ],
          ),
        );
  }

  Widget _buildSinglePostView({required double horizontalPadding, required double verticalPadding}) {
    if (_singlePostStream == null) {
      return const Center(child: Text('Post not found.'));
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _singlePostStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Post not found or may have been removed.'));
        }
        final doc = snapshot.data!;
        final data = doc.data() ?? <String, dynamic>{};
        final post = {'id': doc.id, ...data};
        if (!_isApprovedPost(post)) {
          return RefreshIndicator(
            onRefresh: () async {
              await _loadUser();
              await Future.delayed(const Duration(milliseconds: 150));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text(
                    'This post is not available.',
                    style: TextStyle(
                      color: _subtleInk,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        final postId = doc.id;
        final likedBy = (post['likedBy'] as List?) ?? <dynamic>[];
        likeCounts.putIfAbsent(
          postId,
          () => post['likes_count'] is num ? (post['likes_count'] as num).toInt() : likedBy.length,
        );
        commentCounts.putIfAbsent(postId, () => post['comments_count'] ?? 0);

        return RefreshIndicator(
          onRefresh: () async {
            await _loadUser();
            await Future.delayed(const Duration(milliseconds: 150));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
            children: [
              _buildPostCard(post, key: ValueKey(postId)),
            ],
          ),
        );
      },
    );
  }
}
