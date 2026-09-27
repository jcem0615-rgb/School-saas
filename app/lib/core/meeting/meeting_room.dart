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

/// What to tell somebody when there is no video here.
///
/// Two different reasons, and telling them apart matters because the
/// demo is where people look at this product first. A demo has no
/// school and no server to connect, so saying "the school needs to
/// connect a video server" to somebody trying the demo sends them off
/// to fix something that is not broken.
///
/// Written for whoever is reading it either way -- a teacher with a
/// class waiting, or somebody evaluating the product -- rather than for
/// the person who will do the configuring.
String videoNotConfigured({required bool demo}) => demo
    ? 'Live video is not switched on for this demo. Everything else '
        'about holding a class works here: starting it, who may join, '
        'and the register.'
    : 'Online classes are not set up yet. The school needs to connect a '
        'video server before a lesson can be held here.';
