import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOBILE = ROOT / "apps" / "mobile"


USER_FACING_CONTENT_FILES = (
    MOBILE / "lib/features/content/empty_text_section_screen.dart",
    MOBILE / "lib/features/content/events_screen.dart",
    MOBILE / "lib/features/content/imams_screen.dart",
    MOBILE / "lib/features/content/ahl_al_bayt_content_screen.dart",
    MOBILE / "lib/features/content/content_screen.dart",
    MOBILE / "lib/features/content/quran_library_screen.dart",
    MOBILE / "lib/features/content/quran_text_reader_screen.dart",
    MOBILE / "lib/features/radio/audio_library_screen.dart",
    MOBILE / "lib/features/radio/radio_screen.dart",
    MOBILE / "lib/features/settings/source_catalog_screen.dart",
)


def test_content_and_audio_screens_do_not_launch_external_websites():
    for path in USER_FACING_CONTENT_FILES:
        source = path.read_text(encoding="utf-8")
        assert "launchUrl" not in source, path


def test_audio_playback_and_download_are_gated_by_public_rights_catalogue():
    reader = (
        MOBILE / "lib/features/content/quran_text_reader_screen.dart"
    ).read_text(encoding="utf-8")
    audio_screen = (
        MOBILE / "lib/features/radio/audio_library_screen.dart"
    ).read_text(encoding="utf-8")
    radio = (MOBILE / "lib/features/radio/radio_screen.dart").read_text(
        encoding="utf-8"
    )
    playback = (MOBILE / "lib/core/audio_playback_service.dart").read_text(
        encoding="utf-8"
    )
    pubspec = (MOBILE / "pubspec.yaml").read_text(encoding="utf-8")

    assert "audio_service: ^0.18.19" in pubspec
    assert "class KhazainAudioHandler extends BaseAudioHandler" in playback
    assert "appAudioPlaybackProvider" in audio_screen
    assert "appAudioPlaybackProvider" in reader
    assert "/api/v1/public/catalog/audio" in reader
    assert "playLocal(" in reader
    assert "AudioSource.file" in playback
    assert "uri.scheme != 'https'" in playback
    assert "streaming" not in reader.lower() or "rights" in reader.lower()
    assert "/api/v1/public/catalog/audio" in audio_screen
    assert "can_download" in audio_screen
    assert "download_url" in audio_screen
    assert "licensed_audio" in audio_screen
    assert "Uri.tryParse(url)?.scheme != 'https'" in audio_screen
    assert "AudioPlayer" not in radio
    assert "stream_url" not in radio


def test_quran_audio_index_lists_all_114_surahs_without_fabricating_recordings():
    manifest = json.loads(
        (MOBILE / "assets/data/quran/audio_surahs_manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["total_surahs"] == 114
    assert len(manifest["items"]) == 114
    assert all(item["audio_status"] == "awaiting_verified_recording" for item in manifest["items"])


def test_full_reference_audio_catalog_is_not_packaged_but_user_import_is():
    pubspec = (MOBILE / "pubspec.yaml").read_text(encoding="utf-8")
    assert "assets/data/catalogs/audio_library_catalog.json" not in pubspec
    assert "assets/data/catalogs/shiavoice_recent_library.json" in pubspec


def test_api_content_and_source_text_is_sanitized_before_display():
    content_screen = (
        MOBILE / "lib/features/content/content_screen.dart"
    ).read_text(encoding="utf-8")
    source_screen = (
        MOBILE / "lib/features/settings/source_catalog_screen.dart"
    ).read_text(encoding="utf-8")

    assert "safeDisplayText(" in content_screen
    assert "safeDisplayText(" in source_screen


def test_support_links_and_prayer_api_connection_remain_intact():
    support = (MOBILE / "lib/features/settings/support_sheet.dart").read_text(
        encoding="utf-8"
    )
    prayer = (MOBILE / "lib/core/misr_quran_prayer_times.dart").read_text(
        encoding="utf-8"
    )

    assert "launchUrl" in support
    assert "api.misrquran.gov.eg" in prayer


def test_licensed_text_sections_are_packaged_locally_without_pdf_or_external_readers():
    visits = (
        MOBILE / "lib/features/content/ziyara_library_screen.dart"
    ).read_text(encoding="utf-8")
    local_reader = (
        MOBILE / "lib/features/content/local_text_library.dart"
    ).read_text(encoding="utf-8")
    pubspec = (MOBILE / "pubspec.yaml").read_text(encoding="utf-8")
    router = (MOBILE / "lib/app/router.dart").read_text(encoding="utf-8")
    content = (
        MOBILE / "lib/features/content/content_screen.dart"
    ).read_text(encoding="utf-8")

    assert "PdfViewer" not in visits
    assert "launchUrl" not in visits
    assert "https://" not in visits
    assert "assets/data/library/" in pubspec
    assert (MOBILE / "assets/data/library/index.json").exists()
    assert "ZiyaraVolumeTextScreen" in router
    assert "LocalTextReaderScreen" in router
    assert "LocalTextLibraryScreen" in content
    assert "rootBundle.loadString" in local_reader
    assert "assets/data/library/" in local_reader


def test_local_library_has_licensed_text_in_every_added_section_and_no_quran_or_pdf():
    library = MOBILE / "assets/data/library"
    index = json.loads((library / "index.json").read_text(encoding="utf-8"))
    entries = index["items"]
    expected = {"book", "hadith", "dua", "visit", "ethics", "story"}
    counts = {category: 0 for category in expected}

    assert index["quran_included"] is False
    assert len(entries) >= 60
    for item in entries:
        category = item["category"]
        counts[category] += 1
        assert item["license_id"] in {"CC-BY-4.0", "CC-BY-SA-4.0"}
        assert item["format"] == "txt"
        assert item["offline"] is True
        assert item["content_file"].endswith(".txt")
        body_path = library / item["content_file"]
        assert body_path.exists(), item["id"]
        body = body_path.read_text(encoding="utf-8")
        assert body.strip(), item["id"]
        assert item["sha256"]
        if item["license_id"] == "CC-BY-SA-4.0":
            assert item["source_url"].startswith("https://ar.wikisource.org/")
            assert "ويكي مصدر" in item["attribution"]

    assert set(counts) == expected
    assert all(count > 0 for count in counts.values()), counts
    assert not list(library.rglob("*.pdf"))
    assert (library / "LICENSES_AR.md").exists()
    assert (library / "CATALOG_AR.md").exists()


def test_new_offline_prayer_and_hijri_assets_are_packaged_without_external_links():
    pubspec = (MOBILE / "pubspec.yaml").read_text(encoding="utf-8")
    data = MOBILE / "assets/data"
    assert "assets/data/prayer_times/" in pubspec
    assert "assets/data/shia_occasions_hijri.json" in pubspec
    assert "assets/data/ahl_al_bayt_biographies.json" in pubspec
    assert len(list((data / "prayer_times").glob("*.csv"))) == 18
    occasions = json.loads((data / "shia_occasions_hijri.json").read_text(encoding="utf-8"))
    biographies = json.loads((data / "ahl_al_bayt_biographies.json").read_text(encoding="utf-8"))
    assert len(occasions) >= 1
    assert len(biographies) >= 1
    assert "http://" not in json.dumps(occasions, ensure_ascii=False)
    assert "https://" not in json.dumps(occasions, ensure_ascii=False)
    assert "http://" not in json.dumps(biographies, ensure_ascii=False)
    assert "https://" not in json.dumps(biographies, ensure_ascii=False)


def test_iraqi_prayer_tables_cover_each_city_for_the_full_published_range():
    schedule_dir = MOBILE / "assets/data/prayer_times"
    files = sorted(schedule_dir.glob("*.csv"))
    assert len(files) == 18
    total_records = 0
    expected_columns = [
        "location_id", "date", "hijri_date", "hijri_basis", "city_ar",
        "governorate_ar", "imsak", "fajr", "sunrise", "dhuhr", "asr",
        "sunset", "maghrib", "isha", "midnight",
    ]
    time_fields = ["imsak", "fajr", "sunrise", "dhuhr", "asr", "sunset", "maghrib", "isha", "midnight"]
    for path in files:
        with path.open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            assert reader.fieldnames == expected_columns
            rows = list(reader)
        total_records += len(rows)
        city_rows = {}
        for row in rows:
            city_rows.setdefault(row["city_ar"], []).append(row)
            for key in time_fields:
                assert re.fullmatch(r"(?:[01]\d|2[0-3]):[0-5]\d", row[key]), (path.name, row)
        for city, records in city_rows.items():
            dates = [record["date"] for record in records]
            assert len(records) == 730, (path.name, city, len(records))
            assert dates[0] == "2026-01-01" and dates[-1] == "2027-12-31"
            assert len(set(dates)) == 730
    assert total_records == 119720


def test_sections_open_as_pages_and_source_catalog_ui_is_not_instruction_heavy():
    sections = (MOBILE / "lib/features/sections/sections_screen.dart").read_text(encoding="utf-8")
    router = (MOBILE / "lib/app/router.dart").read_text(encoding="utf-8")
    sources = (MOBILE / "lib/features/settings/source_catalog_screen.dart").read_text(encoding="utf-8")

    assert "context.push(section.route)" in sections
    assert "GoRoute(" in router
    assert "CustomScrollView" in sections
    assert "telegram_library' => 'قناة كتب تيليجرام'" in sources
    assert "unverified_channel_identity" in sources
    assert "هذه قائمة داخلية بالمصادر وشروط الاستخدام" not in sources


def test_telegram_sources_are_catalogued_without_claiming_reuse_rights():
    catalog = json.loads(
        (ROOT / "services/api/app/data/source_catalog.json").read_text(encoding="utf-8")
    )
    by_id = {item["source_id"]: item for item in catalog}
    expected = {
        "SRC-TG-ISLAMICBOOKSSSS",
        "SRC-TG-SHIABOOKS-PDF",
        "SRC-TG-SHIA-LIBRARY1",
        "SRC-TG-SHIALIBRARY-PDF",
        "SRC-TG-SHIITE-NEWS-LIBRARY",
        "SRC-TG-BOOKSSHIET",
        "SRC-TG-HADITHSHIA",
        "SRC-TG-KTOOBH",
        "SRC-TG-ALBURHAN",
    }
    assert expected.issubset(by_id)
    for source_id in expected - {"SRC-TG-SHIA-LIBRARY1"}:
        assert by_id[source_id]["license_status"] == "reference_only_permission_for_reuse_unconfirmed"
    assert by_id["SRC-TG-SHIA-LIBRARY1"]["license_status"] == "unverified_channel_identity"


def test_thaqalayn_api_and_mcp_reference_are_catalogued_with_clear_reuse_limits():
    catalog = json.loads(
        (ROOT / "services/api/app/data/source_catalog.json").read_text(encoding="utf-8")
    )
    by_id = {item["source_id"]: item for item in catalog}

    api = by_id["SRC-THAQALAYN-API"]
    assert api["official_url"] == "https://www.thaqalayn-api.net/"
    assert api["category"] == "shia_hadith_library"
    assert api["license_status"] == "reference_only_permission_for_reuse_unconfirmed"
    assert "لا يستورد قاعدة الخدمة كاملة" in api["notes"]

    mcp = by_id["SRC-THAQALAYN-API-MCP"]
    assert mcp["official_url"] == "https://github.com/MohammedArab1/thaqalayn-api-mcp"
    assert mcp["category"] == "api_integration"
    assert mcp["license_status"] == "check_data_license_before_redistribution"
    assert "ISC" in mcp["notes"] and "MIT" in mcp["notes"]

    source_screen = (
        MOBILE / "lib/features/settings/source_catalog_screen.dart"
    ).read_text(encoding="utf-8")
    assert "'api_integration' => 'تكامل واجهة برمجية'" in source_screen


def test_thaqalayn_parser_exposes_nested_source_gradings_without_creating_its_own_verdict():
    repository = (
        MOBILE / "lib/core/thaqalayn_repository.dart"
    ).read_text(encoding="utf-8")
    test_source = (
        MOBILE / "test/core/thaqalayn_repository_test.dart"
    ).read_text(encoding="utf-8")

    assert "GradingsFull" in repository
    assert "تفصيل التقييم المنقول" in repository
    assert "BehdudiGrading" in repository
    assert "accepts the source TypeScript BookId and Volume field aliases" in test_source
    assert "preserves nested full grading records and scholar references" in test_source


def test_shiavoice_user_export_is_integrated_as_link_only_recent_history():
    asset_path = MOBILE / "assets/data/catalogs/shiavoice_recent_library.json"
    catalog = json.loads(asset_path.read_text(encoding="utf-8"))
    rows = catalog["recent"]
    assert catalog["schema_version"] == 1
    assert len(rows) == 26
    assert len({row["id"] for row in rows}) == 26
    assert sum(row["category"] == "quran" for row in rows) == 8
    assert sum(row["category"] == "adhan" for row in rows) == 10
    assert sum(row["category"] == "duas" for row in rows) == 4
    assert sum(row["category"] == "poems" for row in rows) == 4
    assert catalog["queue"]["track_ids"] == ["np16c"]
    assert catalog["favorites"]["track"] == []
    assert catalog["playlists"] == []
    assert all(re.fullmatch(r"/play-[A-Za-z0-9]+", row["page_path"]) for row in rows)
    assert all(row["duration_seconds"] > 0 for row in rows)
    assert all("stream-" not in row for row in rows)
    assert "لا يخزّن التطبيق الصوت" in catalog["source"]["notice_ar"]
    assert "assets/data/catalogs/shiavoice_recent_library.json" in (
        MOBILE / "pubspec.yaml"
    ).read_text(encoding="utf-8")


def test_every_visible_section_card_has_a_registered_flutter_page():
    catalogue = (MOBILE / "lib/features/sections/section_catalogue.dart").read_text(encoding="utf-8")
    router = (MOBILE / "lib/app/router.dart").read_text(encoding="utf-8")
    section_routes = re.findall(r"\broute:\s*'([^']+)'", catalogue)
    registered_paths = re.findall(r"\bpath:\s*'([^']+)'", router)

    assert len(section_routes) >= 30
    assert len({match for match in re.findall(r"\bid:\s*'([^']+)'", catalogue)}) == len(section_routes)

    def is_registered(route):
        requested = route.split("?", 1)[0]
        requested_parts = requested.strip("/").split("/")
        for registered in registered_paths:
            registered_parts = registered.strip("/").split("/")
            if len(requested_parts) != len(registered_parts):
                continue
            if all(expected == actual or expected.startswith(":")
                   for expected, actual in zip(registered_parts, requested_parts)):
                return True
        return False

    missing = [route for route in section_routes if not is_registered(route)]
    assert not missing, f"Section cards without a Flutter page: {missing}"


def test_shiavoice_section_and_route_open_original_pages_only():
    catalogue = (MOBILE / "lib/features/sections/section_catalogue.dart").read_text(encoding="utf-8")
    router = (MOBILE / "lib/app/router.dart").read_text(encoding="utf-8")
    screen = (MOBILE / "lib/features/radio/shiavoice_library_screen.dart").read_text(encoding="utf-8")
    source_screen = (MOBILE / "lib/features/settings/source_catalog_screen.dart").read_text(encoding="utf-8")
    assert "مكتبة صوت الشيعة" in catalogue and "route: '/shiavoice'" in catalogue
    assert "path: '/shiavoice'" in router and "ShiaVoiceLibraryScreen" in router
    assert "Uri.https('shiavoice.com', path)" in screen
    assert "RegExp(r'^/play-[A-Za-z0-9]+$')" in screen
    assert "LaunchMode.externalApplication" in screen
    assert "لا يقوم التطبيق بتنزيل الصوت" in screen
    assert "'shia_audio_library' => 'مكتبة صوتية شيعية'" in source_screen


def test_shiavoice_source_is_registered_without_granting_audio_redistribution_rights():
    catalog = json.loads((ROOT / "services/api/app/data/source_catalog.json").read_text(encoding="utf-8"))
    by_id = {item["source_id"]: item for item in catalog}
    item = by_id["SRC-SHIAVOICE-USER-EXPORT"]
    assert item["category"] == "shia_audio_library"
    assert item["license_status"] == "reference_only_permission_for_reuse_unconfirmed"
    assert "لا يحفظ الصوت" in item["notes"]


def test_mp3quran_v4_is_integrated_with_code_ids_pagination_etag_and_timing_order():
    router = (MOBILE / "lib/app/router.dart").read_text(encoding="utf-8")
    catalogue = (MOBILE / "lib/features/sections/section_catalogue.dart").read_text(encoding="utf-8")
    quran_screen = (MOBILE / "lib/features/content/quran_library_screen.dart").read_text(encoding="utf-8")
    repository = (MOBILE / "lib/core/mp3quran_v4_repository.dart").read_text(encoding="utf-8")
    screen = (MOBILE / "lib/features/content/quran_recitations_screen.dart").read_text(encoding="utf-8")
    source_screen = (MOBILE / "lib/features/settings/source_catalog_screen.dart").read_text(encoding="utf-8")
    catalog = json.loads((ROOT / "services/api/app/data/source_catalog.json").read_text(encoding="utf-8"))
    by_id = {item["source_id"]: item for item in catalog}

    assert "path: '/quran/recitations'" in router
    assert "route: '/quran/recitations'" in catalogue
    assert "context.push('/quran/recitations')" in quran_screen
    assert "mahmoud-husary/r1" not in repository  # no hard-coded reciter as the default
    assert "_sanitizeNumericResourceIds(_asObject(response.data))" in repository
    assert "key == 'id' && value['code'] is String && entry.value is num" in repository
    assert "If-None-Match" in repository and "status == 304" in repository
    assert "links" in repository and "_nextPageUri(nextUrl)" in repository
    assert "retry-after" in repository.lower() and "rate_limited" in repository
    assert "audio['base']" in repository and "files['original']" in repository
    assert "data['words']" in repository and "occurrence" in repository
    assert "Do not sort or de-duplicate" in repository
    assert "_openWordTimings" in screen and "التوقيتات آلية" in screen
    assert "لا يتيح التطبيق تنزيل التسجيلات" in (
        MOBILE / "lib/features/content/quran_text_reader_screen.dart"
    ).read_text(encoding="utf-8")
    assert "api_streaming_only_rights_review_required" in source_screen

    source = by_id["SRC-MPQURAN-V4-STAGING"]
    assert source["category"] == "quran_audio"
    assert source["license_status"] == "api_streaming_only_rights_review_required"
    assert "Staging" in source["observed"]
    assert "لا يثبت وحده ترخيص كل تسجيل" in source["notes"]
