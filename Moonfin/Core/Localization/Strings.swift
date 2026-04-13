import Foundation

@MainActor
enum Strings {
    private static var bundle: Bundle { LocalizationManager.shared.bundle }

    private static func l(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static func l(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }

    // MARK: - General

    static var loading: String { l("loading") }
    static var cancel: String { l("btn_cancel") }
    static var ok: String { l("lbl_ok") }
    static var yes: String { l("lbl_yes") }
    static var no: String { l("lbl_no") }
    static var save: String { l("lbl_save") }
    static var delete: String { l("lbl_delete") }
    static var edit: String { l("lbl_edit") }
    static var close: String { l("lbl_close") }
    static var back: String { l("lbl_back") }
    static var open: String { l("lbl_open") }
    static var remove: String { l("lbl_remove") }
    static var create: String { l("lbl_create") }
    static var clear: String { l("lbl_clear") }
    static var enabled: String { l("enabled") }
    static var disabled: String { l("disabled") }
    static var none: String { l("lbl_none") }
    static var unknown: String { l("lbl_bracket_unknown") }
    static var filters: String { l("filters") }
    static var noItems: String { l("lbl_no_items") }
    static var empty: String { l("lbl_empty") }
    static var name: String { l("lbl_name") }
    static var random: String { l("random") }

    // MARK: - Navigation

    static var home: String { l("lbl_home") }
    static var search: String { l("lbl_search") }
    static var settings: String { l("settings") }
    static var preferences: String { l("lbl_settings") }
    static var favorites: String { l("lbl_favorites") }
    static var genres: String { l("lbl_genres") }
    static var folders: String { l("lbl_folders") }

    // MARK: - Home Sections

    static var continueWatching: String { l("lbl_continue_watching") }
    static var continueListening: String { l("continue_listening") }
    static var nextUp: String { l("lbl_next_up") }
    static var recentlyAdded: String { l("lbl_latest") }
    static func recentlyAddedIn(_ library: String) -> String { l("lbl_latest_in", library) }
    static var myMedia: String { l("lbl_my_media") }
    static var playlists: String { l("lbl_playlists") }
    static var onNow: String { l("lbl_on_now") }
    static var comingUp: String { l("lbl_coming_up") }
    static var suggestedItems: String { l("lbl_suggested") }

    // MARK: - Content Types

    static var movies: String { l("lbl_movies") }
    static var tvSeries: String { l("lbl_tv_series") }
    static var episodes: String { l("lbl_episodes") }
    static var seasons: String { l("lbl_seasons") }
    static var collections: String { l("lbl_collections") }
    static var albums: String { l("lbl_albums") }
    static var artists: String { l("lbl_artists") }
    static var songs: String { l("lbl_songs") }
    static var videos: String { l("lbl_videos") }
    static var people: String { l("lbl_people") }
    static var programs: String { l("lbl_programs") }
    static var channels: String { l("channels") }
    static var recordings: String { l("lbl_recordings") }
    static var photoAlbums: String { l("photo_albums") }
    static var photos: String { l("photos") }
    static var series: String { l("lbl_series") }
    static var items: String { l("lbl_items") }
    static var other: String { l("lbl_other") }

    // MARK: - Item Details

    static var castAndCrew: String { l("lbl_cast_crew") }
    static var cast: String { l("lbl_cast") }
    static var guestStars: String { l("lbl_guest_stars") }
    static var specials: String { l("lbl_specials") }
    static var trailers: String { l("lbl_trailers") }
    static var additionalParts: String { l("lbl_additional_parts") }
    static var chapters: String { l("chapters") }
    static var similarItems: String { l("lbl_similar_items_library") }
    static var moreLikeThis: String { l("lbl_more_like_this") }
    static var directedBy: String { l("lbl_directed_by") }
    static var born: String { l("lbl_born") }
    static var runtime: String { l("lbl_runtime") }
    static func runtimeHoursMinutes(_ h: Int, _ m: Int) -> String { l("runtime_hours_minutes", h, m) }
    static func runtimeMinutes(_ m: Int) -> String { l("runtime_minutes", m) }
    static func endsAt(_ time: String) -> String { l("lbl_playback_control_ends", time) }
    static func resumeFrom(_ time: String) -> String { l("lbl_resume_from", time) }
    static var playFromBeginning: String { l("lbl_from_beginning") }
    static func seasonNumber(_ n: Int) -> String { l("lbl_season_number", n) }
    static func episodeNumber(_ n: Int) -> String { l("lbl_episode_number", n) }
    static func becauseYouWatched(_ title: String) -> String { l("because_you_watched", title) }

    // MARK: - Playback

    static var play: String { l("lbl_play") }
    static var pause: String { l("lbl_pause") }
    static var playAll: String { l("lbl_play_all") }
    static var shuffleAll: String { l("lbl_shuffle_all") }
    static var playFirstUnwatched: String { l("lbl_play_first_unwatched") }
    static var addToQueue: String { l("lbl_add_to_queue") }
    static var clearQueue: String { l("lbl_clear_queue") }
    static var removeFromQueue: String { l("lbl_remove_from_queue") }
    static var nowPlaying: String { l("lbl_now_playing") }
    static var playFromHere: String { l("lbl_play_from_here") }
    static var instantMix: String { l("lbl_instant_mix") }
    static var nextEpisode: String { l("lbl_next_episode") }
    static var previousEpisode: String { l("lbl_previous_episode") }
    static var goToSeries: String { l("lbl_goto_series") }
    static var audioTrack: String { l("lbl_audio_track") }
    static var subtitleTrack: String { l("lbl_subtitle_track") }
    static var subtitleDelay: String { l("lbl_subtitle_delay") }
    static var audioDelay: String { l("lbl_audio_delay") }
    static var playbackSpeed: String { l("lbl_playback_speed") }
    static var qualityProfile: String { l("lbl_quality_profile") }
    static var selectVersion: String { l("select_version") }
    static var zoom: String { l("lbl_zoom") }
    static var autoCrop: String { l("lbl_auto_crop") }
    static var stretch: String { l("lbl_stretch") }
    static var fit: String { l("lbl_fit") }
    static var rewind: String { l("rewind") }
    static var fastForward: String { l("fast_forward") }
    static var currentQueue: String { l("current_queue") }
    static var playerLyrics: String { l("player_lyrics") }
    static var playerQueue: String { l("player_queue") }
    static var playerPlayNext: String { l("player_play_next") }
    static var playerDownloadSubtitles: String { l("player_download_subtitles") }
    static var playerDownloadSubtitlesTitle: String { l("player_download_subtitles_title") }
    static var playerOpenSubtitlesSearch: String { l("player_open_subtitles_search") }
    static var playerSpeedNormal: String { l("player_speed_normal") }
    static var playerSearching: String { l("player_searching") }
    static var playerSubtitleSearchFailed: String { l("player_subtitle_search_failed") }
    static var playerSubtitleDownloadFailed: String { l("player_subtitle_download_failed") }
    static var playerStillWatchingDetail: String { l("player_still_watching_detail") }
    static var playerContinue: String { l("player_continue") }
    static var playerStop: String { l("player_stop") }
    static var playerPrevious: String { l("player_previous") }
    static var playerNext: String { l("player_next") }
    static var playerSubtitleDelayDown: String { l("player_subtitle_delay_down") }
    static var playerSubtitleDelayReset: String { l("player_subtitle_delay_reset") }
    static var playerSubtitleDelayUp: String { l("player_subtitle_delay_up") }
    static var playerPlaybackInformation: String { l("player_playback_information") }
    static var playerPlaybackSection: String { l("player_playback_section") }
    static var playerPlayMethod: String { l("player_play_method") }
    static var playerBackend: String { l("player_backend") }
    static var playerFallback: String { l("player_fallback") }
    static var playerContainer: String { l("player_container") }
    static var playerBitrate: String { l("player_bitrate") }
    static var playerVideoSection: String { l("player_video_section") }
    static var playerResolution: String { l("player_resolution") }
    static var playerHdr: String { l("player_hdr") }
    static var playerPlayerType: String { l("player_player_type") }
    static var playerCodec: String { l("player_codec") }
    static var playerBitDepth: String { l("player_bit_depth") }
    static var playerVideoBitrate: String { l("player_video_bitrate") }
    static var playerFrames: String { l("player_frames") }
    static var playerHdrMetadata: String { l("player_hdr_metadata") }
    static var playerMaxCll: String { l("player_max_cll") }
    static var playerMaxFall: String { l("player_max_fall") }
    static var playerTelemetry: String { l("player_telemetry") }
    static var playerToneMap: String { l("player_tone_map") }
    static var playerSinkHdr: String { l("player_sink_hdr") }
    static var playerContent: String { l("player_content") }
    static var playerInColor: String { l("player_in_color") }
    static var playerOutColor: String { l("player_out_color") }
    static var playerTarget: String { l("player_target") }
    static var playerActiveToneMapping: String { l("player_active_tone_mapping") }
    static var playerHardwareDecode: String { l("player_hardware_decode") }
    static var playerAudioSection: String { l("player_audio_section") }
    static var playerTrack: String { l("player_track") }
    static var playerChannels: String { l("player_channels") }
    static var playerAudioBitrate: String { l("player_audio_bitrate") }
    static var playerSampleRate: String { l("player_sample_rate") }
    static var playerFormat: String { l("player_format") }
    static var playerType: String { l("player_type") }
    static var playerExternal: String { l("player_external") }
    static var playerEmbedded: String { l("player_embedded") }
    static var playerUnknown: String { l("player_unknown") }
    static var playerUnknownShort: String { l("player_unknown_short") }
    static var playerNA: String { l("player_na") }
    static var playerDolbyVision: String { l("player_dolby_vision") }
    static var playerHdr10Plus: String { l("player_hdr10_plus") }
    static var playerHdr10: String { l("player_hdr10") }
    static var playerHlg: String { l("player_hlg") }
    static var playerHdrValue: String { l("player_hdr_value") }
    static var playerSdr: String { l("player_sdr") }
    static var playerCodecHevc: String { l("player_codec_hevc") }
    static var playerCodecAvc: String { l("player_codec_avc") }
    static var playerCodecAv1: String { l("player_codec_av1") }
    static var playerCodecVp9: String { l("player_codec_vp9") }
    static var playerAudioCodecEac3: String { l("player_audio_codec_eac3") }
    static var playerAudioCodecAc3: String { l("player_audio_codec_ac3") }
    static var playerAudioCodecTrueHd: String { l("player_audio_codec_truehd") }
    static var playerAudioCodecDts: String { l("player_audio_codec_dts") }
    static var playerAudioCodecAac: String { l("player_audio_codec_aac") }
    static var playerAudioCodecFlac: String { l("player_audio_codec_flac") }
    static var playerAudioCodecOpus: String { l("player_audio_codec_opus") }
    static var playerAudioCodecVorbis: String { l("player_audio_codec_vorbis") }
    static var playerMono: String { l("player_mono") }
    static var playerStereo: String { l("player_stereo") }
    static var playerBookCouldNotConnect: String { l("player_book_could_not_connect") }
    static var playerBookUnsupportedFormat: String { l("player_book_unsupported_format") }
    static var playerBookNoReadablePages: String { l("player_book_no_readable_pages") }
    static var playerBookUnableToLoad: String { l("player_book_unable_to_load") }
    static var playerBookDownloadFailed: String { l("player_book_download_failed") }
    static var playerBookInvalidPdf: String { l("player_book_invalid_pdf") }
    static var playerBookCbrNeedsServerChapters: String { l("player_book_cbr_needs_server_chapters") }
    static var playerBookInvalidCbz: String { l("player_book_invalid_cbz") }
    static var playerBookNoChapters: String { l("player_book_no_chapters") }
    static var playerBookComicPagesFailed: String { l("player_book_comic_pages_failed") }
    static func playerTrackCount(_ count: Int) -> String { l("player_track_count", count) }
    static func playerChapter(_ number: Int) -> String { l("player_chapter", number) }
    static func playerSubtitleDelay(_ delay: String) -> String { l("player_subtitle_delay", delay) }
    static func playerNoSubtitlesFound(_ language: String) -> String { l("player_no_subtitles_found", language) }
    static func playerFpsSuffix(_ fps: Int) -> String { l("player_fps_suffix", fps) }
    static func playerResolutionValue(_ width: Int, _ height: Int, _ fpsSuffix: String) -> String { l("player_resolution_value", width, height, fpsSuffix) }
    static func playerBitDepthValue(_ bitDepth: Int) -> String { l("player_bit_depth_value", bitDepth) }
    static func playerFramesValue(_ decoded: String, _ dropped: String) -> String { l("player_frames_value", decoded, dropped) }
    static func playerNitsValue(_ value: String) -> String { l("player_nits_value", value) }
    static func playerEmpty(_ count: Int) -> String { l("player_empty", count) }
    static func playerColorPair(_ first: String, _ second: String) -> String { l("player_color_pair", first, second) }
    static func playerSampleRateValue(_ khz: Double) -> String { l("player_sample_rate_value", khz) }
    static func playerBitrateMbps(_ mbps: Double) -> String { l("player_bitrate_mbps", mbps) }
    static func playerBitrateKbps(_ kbps: Int) -> String { l("player_bitrate_kbps", kbps) }
    static func playerBitrateBps(_ bps: Int) -> String { l("player_bitrate_bps", bps) }
    static func playerDolbyVisionProfile(_ profile: String, _ level: String) -> String { l("player_dolby_vision_profile", profile, level) }
    static func playerCodecProfileSuffix(_ profile: String) -> String { l("player_codec_profile_suffix", profile) }
    static func playerCodecLevelSuffix(_ level: Int) -> String { l("player_codec_level_suffix", level) }
    static func playerChannelsCount(_ channels: Int) -> String { l("player_channels_count", channels) }

    // MARK: - Playback Status

    static var videoError: String { l("video_error_unknown_error") }
    static var noPlayableItems: String { l("msg_no_playable_items") }
    static var playbackNotAllowed: String { l("msg_playback_not_allowed") }
    static var cannotPlay: String { l("msg_cannot_play") }
    static var seekError: String { l("seek_error") }
    static var playerError: String { l("player_error") }
    static var tooManyErrors: String { l("too_many_errors") }
    static var subtitlesLoading: String { l("msg_subtitles_loading") }

    // MARK: - Media Segments

    static var skipIntro: String { l("skip_intro") }
    static var skipOutro: String { l("skip_outro") }
    static var skipRecap: String { l("skip_recap") }
    static var skipCommercial: String { l("skip_commercial") }
    static var skipPreview: String { l("skip_preview") }
    static func playNextCountdown(_ s: Int) -> String { l("play_next_episode_countdown", s) }
    static var stillWatchingLabel: String { l("still_watching_label") }

    // MARK: - Item Actions

    static var favorite: String { l("lbl_favorite") }
    static var addFavorite: String { l("lbl_add_favorite") }
    static var removeFavorite: String { l("lbl_remove_favorite") }
    static var markPlayed: String { l("lbl_mark_played") }
    static var markUnplayed: String { l("lbl_mark_unplayed") }
    static var watched: String { l("lbl_watched") }
    static var unwatched: String { l("lbl_unwatched") }
    static var addToPlaylist: String { l("lbl_add_to_playlist") }
    static var createNewPlaylist: String { l("lbl_create_new_playlist") }
    static var removeFromPlaylist: String { l("lbl_remove_from_playlist") }
    static var addToWatchList: String { l("lbl_add_to_watch_list") }
    static var removeFromWatchList: String { l("lbl_remove_from_watch_list") }

    // MARK: - Auth / Login

    static var signIn: String { l("lbl_sign_in") }
    static var signOut: String { l("lbl_sign_out") }
    static var switchUser: String { l("lbl_switch_user") }
    static var addUser: String { l("add_user") }
    static var enterServerAddress: String { l("lbl_enter_server_address") }
    static var whoIsWatching: String { l("who_is_watching") }
    static var authenticating: String { l("login_authenticating") }
    static var invalidCredentials: String { l("login_invalid_credentials") }
    static var serverUnavailable: String { l("login_server_unavailable") }
    static func connectingTo(_ server: String) -> String { l("login_connect_to", server) }
    static var usernameField: String { l("input_username") }
    static var passwordField: String { l("input_password") }
    static var connect: String { l("action_connect") }
    static var usePassword: String { l("action_use_password") }
    static var useQuickConnect: String { l("action_use_quickconnect") }
    static var savedServers: String { l("saved_servers") }
    static var discoveredServers: String { l("discovered_servers_title") }
    static var noDiscoveredServers: String { l("discovered_servers_empty") }
    static var welcomeTitle: String { l("welcome_title") }
    static var welcomeContent: String { l("welcome_content") }
    static var selectServer: String { l("lbl_select_server") }
    static var removeServer: String { l("lbl_remove_server") }
    static var manageServers: String { l("lbl_manage_servers") }
    static var gotIt: String { l("btn_got_it") }

    // MARK: - PIN

    static var pinCode: String { l("lbl_pin_code") }
    static var enterPin: String { l("lbl_enter_pin") }
    static var enterNewPin: String { l("lbl_enter_new_pin") }
    static var confirmPin: String { l("lbl_confirm_pin") }
    static var pinSet: String { l("lbl_pin_code_set") }
    static var pinChanged: String { l("lbl_pin_code_changed") }
    static var pinRemoved: String { l("lbl_pin_code_removed") }
    static var pinIncorrect: String { l("lbl_pin_code_incorrect") }
    static var pinMismatch: String { l("lbl_pin_code_mismatch") }
    static var forgotPin: String { l("lbl_forgot_pin") }

    // MARK: - Server Issues

    static var serverUnableToConnect: String { l("server_issue_unable_to_connect") }
    static var serverInvalidProduct: String { l("server_issue_invalid_product") }
    static var serverMissingVersion: String { l("server_issue_missing_version") }
    static func serverUnsupportedVersion(_ v: String) -> String { l("server_issue_unsupported_version", v) }
    static var serverTimeout: String { l("server_issue_timeout") }
    static var serverSSLFailed: String { l("server_issue_ssl_handshake") }
    static var serverSetupIncomplete: String { l("server_setup_incomplete") }

    // MARK: - Settings

    static var authentication: String { l("pref_authentication_cat") }
    static var customization: String { l("pref_customization") }
    static var playbackSettings: String { l("pref_playback") }
    static var about: String { l("pref_about_title") }
    static var telemetry: String { l("pref_telemetry_category") }
    static var screensaver: String { l("pref_screensaver") }
    static var appearance: String { l("pref_appearance") }
    static var theme: String { l("pref_theme") }
    static var homeSections: String { l("home_sections") }
    static var focusColor: String { l("pref_focus_color") }
    static var librariesSettings: String { l("pref_libraries") }
    static var clockDisplay: String { l("pref_clock_display") }
    static var watchedIndicator: String { l("pref_watched_indicator") }
    static var maxBitrate: String { l("pref_max_bitrate_title") }
    static var maxResolution: String { l("pref_max_resolution_title") }
    static var subtitlesSettings: String { l("pref_subtitles") }
    static var mediaSegmentActions: String { l("pref_mediasegment_actions") }
    static var nextUpSettings: String { l("pref_playback_next_up") }
    static var prerollsEnabled: String { l("pref_prerolls_enabled") }
    static var prerollsEnabledDescription: String { l("pref_prerolls_enabled_description") }
    static var navbarPosition: String { l("pref_navbar_position") }
    static var liveTvSettings: String { l("pref_live_tv_cat") }
    static var licenses: String { l("licenses_link") }
    static var loginDescription: String { l("pref_login_description") }
    static var customizationDescription: String { l("pref_customization_description") }
    static var playbackDescription: String { l("pref_playback_description") }
    static var telemetryDescription: String { l("pref_telemetry_description") }
    static var plugin: String { l("pref_plugin_settings") }
    static var pluginSync: String { l("pref_plugin_sync_enable") }
    static var pluginSyncDescription: String { l("pref_plugin_sync_description") }
    static var licensesDescription: String { l("licenses_link_description") }
    static var advanced: String { l("advanced_settings") }
    static var liveTvPreferences: String { l("live_tv_preferences") }
    static var mediaSegmentsSettings: String { l("pref_playback_media_segments") }
    static var trickPlay: String { l("settings_trickplay") }
    static var trickPlayDescription: String { l("settings_trickplay_description") }
    static var authenticationSummary: String { l("settings_authentication_summary") }
    static var customizationSummary: String { l("settings_customization_summary") }
    static var homeSummary: String { l("settings_home_summary") }
    static var pluginSummary: String { l("settings_plugin_summary") }
    static var screensaverSummary: String { l("settings_screensaver_summary") }
    static var syncPlaySummary: String { l("settings_syncplay_summary") }
    static var parentalControlsSummary: String { l("settings_parental_controls_summary") }
    static var aboutSummary: String { l("settings_about_summary") }
    static var nextUpBehaviorDescription: String { l("settings_playback_next_up_behavior_description") }
    static var nextUpBehaviorTitle: String { l("pref_next_up_behavior_title") }
    static var nextUpTimeoutTitle: String { l("pref_next_up_timeout_title") }
    static var nextUpTimeoutDescription: String { l("settings_playback_next_up_timeout_description") }
    static var stillWatchingPrompt: String { l("settings_playback_still_watching") }
    static var stillWatchingPromptDescription: String { l("settings_playback_still_watching_description") }
    static var audioBehavior: String { l("settings_playback_audio_behavior") }
    static var audioBehaviorDescription: String { l("settings_playback_audio_behavior_description") }
    static var audioOutput: String { l("lbl_audio_output") }
    static var slideshowInterval: String { l("settings_slideshow_interval") }
    static var slideshowIntervalDescription: String { l("settings_slideshow_interval_description") }
    static var mediaSegmentsDescription: String { l("settings_media_segments_description") }
    static var advancedDescription: String { l("settings_advanced_description") }
    static var resumePreroll: String { l("lbl_resume_preroll") }
    static var skipForwardLength: String { l("skip_forward_length") }
    static var unpauseRewind: String { l("unpause_rewind_duration") }
    static var videoStartDelay: String { l("video_start_delay") }
    static var defaultZoom: String { l("default_video_zoom") }
    static var aboutVersion: String { l("settings_about_version") }
    static var aboutBuild: String { l("settings_about_build") }
    static var noLicensesFound: String { l("settings_licenses_none") }
    static var toolbar: String { l("settings_toolbar") }
    static var backgrounds: String { l("settings_backgrounds") }
    static var previewsAndMusic: String { l("settings_plugin_previews_music") }
    static var integrations: String { l("settings_integrations") }
    static var pluginToolbarSummary: String { l("settings_plugin_toolbar_summary") }
    static var pluginMediaBarSummary: String { l("settings_plugin_media_bar_summary") }
    static var pluginBackgroundsSummary: String { l("settings_plugin_backgrounds_summary") }
    static var pluginPreviewsMusicSummary: String { l("settings_plugin_previews_music_summary") }
    static var pluginIntegrationsSummary: String { l("settings_plugin_integrations_summary") }
    static var fetchLimit: String { l("settings_fetch_limit") }
    static var syncPlayMinDelaySpeed: String { l("settings_syncplay_min_delay_speed") }
    static var syncPlayMaxDelaySpeed: String { l("settings_syncplay_max_delay_speed") }
    static var syncPlaySpeedDuration: String { l("settings_syncplay_speed_duration") }
    static var syncPlayMinDelaySkip: String { l("settings_syncplay_min_delay_skip") }
    static var syncPlayExtraOffset: String { l("settings_syncplay_extra_offset") }
    static var channelOrder: String { l("settings_channel_order") }
    static var comingSoon: String { l("settings_coming_soon") }
    static var licenseLabel: String { l("license_license") }
    static func currentValue(_ value: String) -> String { l("settings_current_value", value) }
    static func episodeCount(_ count: Int) -> String { l("settings_episode_count", count) }
    static var secondsShort: String { l("unit_seconds_short") }
    static var millisecondsShort: String { l("unit_milliseconds_short") }

    // MARK: - Settings Values

    static var imageTypePoster: String { l("image_type_poster") }
    static var imageTypeThumbnail: String { l("image_type_thumbnail") }
    static var imageTypeBanner: String { l("image_type_banner") }
    static var imageTypeSquare: String { l("image_type_square") }
    static var always: String { l("lbl_always") }
    static var never: String { l("lbl_never") }

    // MARK: - Sorting / Filtering

    static var sortBy: String { l("lbl_sort_by") }
    static var dateAdded: String { l("lbl_date_added") }
    static var premierDate: String { l("lbl_premier_date") }
    static var criticRating: String { l("lbl_critic_rating") }
    static var communityRating: String { l("lbl_community_rating") }
    static var rating: String { l("lbl_rating") }
    static var allItems: String { l("lbl_all_items") }
    static var byLetter: String { l("lbl_by_letter") }
    static var byName: String { l("lbl_by_name") }

    // MARK: - Live TV

    static var liveTvGuide: String { l("lbl_live_tv_guide") }
    static var schedule: String { l("lbl_schedule") }
    static var record: String { l("lbl_record") }
    static var cancelRecording: String { l("lbl_cancel_recording") }
    static var seriesRecordings: String { l("lbl_series_recordings") }
    static var recentRecordings: String { l("lbl_recent_recordings") }
    static var noRecordings: String { l("lbl_no_recordings") }
    static var today: String { l("lbl_today") }
    static var tomorrow: String { l("lbl_tomorrow") }
    static var tuneToChannel: String { l("lbl_tune_to_channel") }
    static var sports: String { l("lbl_sports") }
    static var kids: String { l("lbl_kids") }
    static var news: String { l("lbl_news") }
    static var premiere: String { l("lbl_premiere") }

    // MARK: - Media Bar

    static var mediaBarTitle: String { l("pref_media_bar_title") }
    static var mediaBarLoading: String { l("lbl_media_bar_loading") }
    static var mediaBarError: String { l("lbl_media_bar_error") }

    // MARK: - Jellyseerr

    static var jellyseerr: String { l("jellyseerr") }
    static var jellyseerrEnabled: String { l("jellyseerr_enabled") }
    static var jellyseerrServerUrl: String { l("jellyseerr_server_url") }
    static var jellyseerrTestConnection: String { l("jellyseerr_test_connection") }
    static var jellyseerrConnectionSuccess: String { l("jellyseerr_connection_success") }
    static var jellyseerrConnectionError: String { l("jellyseerr_connection_error") }

    // MARK: - SyncPlay

    static var syncPlay: String { l("syncplay") }
    static var syncPlayCreateGroup: String { l("syncplay_create_group") }
    static var syncPlayJoinGroup: String { l("syncplay_join_group") }
    static var syncPlayLeaveGroup: String { l("syncplay_leave_group") }
    static var syncPlayNoGroups: String { l("syncplay_no_groups") }

    // MARK: - Parental Controls

    static var parentalControls: String { l("pref_parental_controls") }

    // MARK: - Updates

    static var checkForUpdates: String { l("pref_check_for_updates") }
    static var noUpdatesAvailable: String { l("msg_no_updates_available") }
    static func updateAvailable(_ version: String) -> String { l("msg_update_available", version) }

    // MARK: - Exit

    static var exit: String { l("lbl_exit") }
    static var exitConfirmTitle: String { l("exit_confirmation_title") }
    static var exitConfirmMessage: String { l("exit_confirmation_message") }

    // MARK: - Errors

    static var errorLoadingData: String { l("msg_error_loading_data") }
    static var shuffleError: String { l("shuffle_error") }
    static var shuffleNoItems: String { l("shuffle_no_items_found") }
}
