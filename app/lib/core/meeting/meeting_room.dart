/// Where a school's online classes happen.
///
/// One shape now, deliberately. There used to be a second -- an embedded
/// meeting from somebody else's deployment -- and it is gone because it
/// could not be made to work: an embedded page is a page a server is
/// entitled to refuse, two public Jitsi deployments refused it, and
/// nothing on this side of an iframe reaches across that. It also could
/// not have carried a class: everybody sending their own video to
/// everybody else stops working several times short of sixty.
///
/// So the lesson runs through a media server and LogicClass draws it
/// itself, in its own widgets. Nothing to embed, nothing to refuse, and
/// one upload per person however many are in the room.
///
/// The server's address is not compiled in: it arrives with the pass
/// from `issueMeetingToken`, so a school can move to a different one --
/// or to its own -- without rebuilding the app. See
/// docs/44-a-class-of-sixty.md.
library;

/// Whether this school has somewhere to hold a video class.
///
/// False until `LIVEKIT_URL`, `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET`
/// are set on the Functions deployment. Until then the screens say so
/// plainly rather than sending a class at something that will not work,
/// which is what the old fallback did.
bool schoolHasVideo(String provider, String? url) =>
    provider == 'livekit' && url != null && url.isNotEmpty;

/// What to tell somebody when it has not been set up.
///
/// Written for whoever is reading it -- a teacher with a class waiting,
/// not the person who will configure it.
const videoNotConfigured =
    'Online classes are not set up yet. The school needs to connect a '
    'video server before a lesson can be held here.';
