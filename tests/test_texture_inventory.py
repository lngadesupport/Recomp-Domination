import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('texture_inventory', Path(__file__).parents[1] / 'scripts/inventory_texture_dumps.py')
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)


class TextureInventoryTests(unittest.TestCase):
    def test_mip_dimensions(self):
        info = inventory.parse_name('abc-def-00001994-mip2.png')
        self.assertEqual((info['psm'], info['base_width'], info['base_height']), (20, 64, 64))
        self.assertEqual((info['expected_width'], info['expected_height']), (16, 16))

    def test_no_palette_and_alpha_fields(self):
        bits = 19 | (5 << 6) | (7 << 10) | (33 << 15) | (1 << 23) | (128 << 24)
        info = inventory.parse_name(f'abc-{bits:08x}.png')
        self.assertEqual((info['palette_hash'], info['ta0'], info['aem'], info['ta1']), ('0', 33, 1, 128))

    def test_unsupported_names_are_not_guessed(self):
        for name in ['../abc-def-00001994.png', 'abc-def-r32x32-00001994.png', 'abc-def-00001994-mip999.png']:
            with self.subTest(name=name), self.assertRaises(ValueError):
                inventory.parse_name(name)

    def test_pixels_unchanged_and_corruption_recorded(self):
        try:
            from PIL import Image
        except ImportError:
            self.skipTest('Pillow not installed')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / 'abc-def-00000014.png'
            Image.new('RGBA', (1, 1), (12, 34, 56, 128)).save(path)
            before = path.read_bytes()
            (root / 'abcd-def-00000014.png').write_bytes(b'invalid png')
            report = inventory.inspect(root)
            self.assertEqual((report['images'], len(report['errors'])), (1, 1))
            self.assertEqual(report['textures'][0]['alpha_extrema'], [128, 128])
            self.assertEqual(path.read_bytes(), before)


if __name__ == '__main__':
    unittest.main()
