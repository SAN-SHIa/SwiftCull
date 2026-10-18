# SwiftCull website

The static website for [SwiftCull](https://github.com/SAN-SHIa/SwiftCull), a free, open-source photo culling app for macOS.

Website: <https://san-shia.github.io/SwiftCull/>

## Preview locally

Run from this branch's root directory:

```bash
python3 -m http.server 4173 --bind 127.0.0.1
```

Open <http://127.0.0.1:4173/>. No build step or package installation is required.

## Publish

GitHub Pages serves the root of the `gh-pages` branch. Pushing updates to this branch republishes the site. The `.nojekyll` file keeps this a plain static site. Native app development and releases use `main`.

The first-visit language is English. Visitors can switch to Chinese, change appearance, browse product screenshots, and try the keyboard-accessible photo rating demo. Language and appearance preferences are stored locally; demo ratings stay in page memory.

## Assets and license

Product screenshots come from the main branch's `assets/pics/previews/`. Photo details are cropped from `assets/pics/dark.png`. The app icon comes from the app's asset catalog. Fonts use the visitor's installed system fonts; no third-party runtime libraries or font downloads are required.

Website code uses the repository's [MIT License](LICENSE). Existing third-party assets retain their original licenses; see the project's [third-party notices](https://github.com/SAN-SHIa/SwiftCull/blob/main/THIRD_PARTY_NOTICES.md).

The contributors section welcomes code, design, documentation, testing, and ideas. The acknowledgements include code and other contributions, based on GitHub records and maintainer confirmation. The GitHub contribution history reflects platform-recognized code commits, rather than every form of contribution. Profile pictures come from the contributors’ public GitHub profiles and are used for attribution. Their rights remain with the respective owners and are not covered by the website code’s MIT License.
