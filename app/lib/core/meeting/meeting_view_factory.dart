/// The embedded meeting surface, where the platform has one.
library;

export 'meeting_view_stub.dart'
    if (dart.library.js_interop) 'meeting_view_web.dart';
