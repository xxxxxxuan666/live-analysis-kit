import importlib.util
from pathlib import Path


SCRIPT = Path(__file__).with_name("resolve-douyin-live-metadata.py")
spec = importlib.util.spec_from_file_location("resolver", SCRIPT)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


def assert_equal(actual, expected, message):
    if actual != expected:
        raise AssertionError(f"{message}: expected {expected!r}, got {actual!r}")


def main():
    title = "\u4e09\u56fd\u5929\u4e0b\u5f52\u5fc3-\u5c06\u661f\u8f6c\u4e16\u7684\u6296\u97f3\u76f4\u64ad\u95f4 - \u6296\u97f3\u76f4\u64ad"
    room_name, source = resolver.extract_room_name(title, "", "619880060102")
    assert_equal(room_name, "\u4e09\u56fd\u5929\u4e0b\u5f52\u5fc3-\u5c06\u661f\u8f6c\u4e16", "room name should keep Douyin title content before the platform suffix")
    assert_equal(source, "page_title_or_visible_text", "room source")

    game, game_source = resolver.infer_game_product(room_name, title, "")
    assert_equal(game, "\u4e09\u56fd\u5929\u4e0b\u5f52\u5fc3", "game product should be inferred from the left side of a title dash")
    assert_equal(game_source, "title_prefix_before_dash", "game source")

    winter_title = "\u65e0\u5c3d\u51ac\u65e5\u5b98\u65b9\u7684\u6296\u97f3\u76f4\u64ad\u95f4 - \u6296\u97f3\u76f4\u64ad"
    winter_room, _ = resolver.extract_room_name(winter_title, "", "840625445876")
    assert_equal(winter_room, "\u65e0\u5c3d\u51ac\u65e5\u5b98\u65b9", "room name without title dash should still be cleaned")

    print("metadata resolver checks passed")


if __name__ == "__main__":
    main()
