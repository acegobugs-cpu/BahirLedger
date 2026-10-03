/// Organization data is deliberately separate from the account /me model.
enum OrganizationRole { owner, member }

enum InvitationStatus { pending, accepted, revoked, expired }

Map<String, dynamic> onboardingObject(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException();
  return value;
}

String onboardingText(Object? value, {int maximum = 120}) {
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.length > maximum ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

String onboardingId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException();
  }
  return value;
}

DateTime onboardingDate(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,9})?(?:Z|\+00:00)$',
      ).hasMatch(value)) {
    throw const FormatException();
  }
  final date = DateTime.parse(value).toUtc();
  if (date.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
    throw const FormatException();
  }
  return date;
}

bool validInvitationCode(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);

String invitationEmail(Object? value) {
  final email = onboardingText(value, maximum: 254);
  if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(email)) {
    throw const FormatException();
  }
  return email;
}

class OrganizationMembership {
  OrganizationMembership.fromJson(Object? value) {
    final json = onboardingObject(value);
    organizationId = onboardingId(json['organizationId']);
    organizationName = onboardingText(json['organizationName']);
    role = switch (json['role']) {
      'OWNER' => OrganizationRole.owner,
      'MEMBER' => OrganizationRole.member,
      _ => throw const FormatException(),
    };
  }
  late final String organizationId;
  late final String organizationName;
  late final OrganizationRole role;
}

class OrganizationBootstrap {
  OrganizationBootstrap.fromJson(Object? value) {
    final json = onboardingObject(value);
    id = onboardingId(json['id']);
    name = onboardingText(json['name']);
    expiresAt = onboardingDate(json['expiresAt']);
  }
  late final String id;
  late final String name;
  late final DateTime expiresAt;
}

class OnboardingContext {
  OnboardingContext.fromJson(Object? value) {
    final json = onboardingObject(value);
    if (!json.containsKey('membership') ||
        !json.containsKey('bootstrap') ||
        (json['membership'] != null && json['bootstrap'] != null)) {
      throw const FormatException();
    }
    membership = json['membership'] == null
        ? null
        : OrganizationMembership.fromJson(json['membership']);
    bootstrap = json['bootstrap'] == null
        ? null
        : OrganizationBootstrap.fromJson(json['bootstrap']);
  }
  late final OrganizationMembership? membership;
  late final OrganizationBootstrap? bootstrap;
}

class OrganizationInvitation {
  OrganizationInvitation.fromJson(Object? value) {
    final json = onboardingObject(value);
    id = onboardingId(json['id']);
    email = invitationEmail(json['email']);
    expiresAt = onboardingDate(json['expiresAt']);
    status = switch (json['status']) {
      'PENDING' => InvitationStatus.pending,
      'ACCEPTED' => InvitationStatus.accepted,
      'REVOKED' => InvitationStatus.revoked,
      'EXPIRED' => InvitationStatus.expired,
      _ => throw const FormatException(),
    };
  }
  late final String id;
  late final String email;
  late final DateTime expiresAt;
  late final InvitationStatus status;

  static List<OrganizationInvitation> listFromJson(Object? value) {
    final list = onboardingObject(value)['invitations'];
    if (list is! List) throw const FormatException();
    final result = list.map(OrganizationInvitation.fromJson).toList();
    if (result.map((item) => item.id.toLowerCase()).toSet().length !=
        result.length) {
      throw const FormatException();
    }
    return List.unmodifiable(result);
  }
}

class InvitationPreview {
  InvitationPreview.fromJson(Object? value) {
    final json = onboardingObject(value);
    organizationName = onboardingText(json['organizationName']);
    expiresAt = onboardingDate(json['expiresAt']);
  }
  late final String organizationName;
  late final DateTime expiresAt;
}

/// Ephemeral response only. Never persist or include the code in diagnostics.
class IssuedInvitation {
  IssuedInvitation.fromJson(Object? value) {
    final json = onboardingObject(value);
    invitation = OrganizationInvitation.fromJson(json['invitation']);
    final token = json['token'];
    if (token is! String ||
        !validInvitationCode(token) ||
        invitation.status != InvitationStatus.pending) {
      throw const FormatException();
    }
    code = token;
  }
  late final OrganizationInvitation invitation;
  late final String code;
  @override
  String toString() => 'IssuedInvitation([redacted])';
}
