/// Address shape Auth can mail to: one `@`, no spaces, a dot in the domain.
/// Recovery and confirmation mails are not requested for anything else; an
/// empty field otherwise reached Auth as `/recover` and `/resend` 400s.
bool motionEmailLooksDeliverable(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
