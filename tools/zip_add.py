# Adds a folder's files to a zip, beside what's in it, leaving the entries
# already there as they are, Unix permissions and all: the macOS app's
# executables need their x bits, which a zip rewritten by .NET loses.
# Used by tools/build_desktop.ps1.
# Usage: python -I zip_add.py <zip> <folder>
import os
import sys
import zipfile

zip_path, folder = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(zip_path, "a", zipfile.ZIP_DEFLATED) as archive:
    for base, _dirs, files in os.walk(folder):
        for name in sorted(files):
            path = os.path.join(base, name)
            info = zipfile.ZipInfo.from_file(path, os.path.relpath(path, folder).replace(os.sep, "/"))
            info.create_system = 3  # Unix, like the app's own entries
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as source:
                archive.writestr(info, source.read())
