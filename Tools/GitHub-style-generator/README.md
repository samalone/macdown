# GitHub Style Generator

Generates MacDown's **GitHub-2020** preview style
(`MacDown/Resources/Styles/GitHub-2020.css`) from GitHub's published markdown
CSS — the maintained
[github-markdown-css](https://github.com/sindresorhus/github-markdown-css)
package, served prebuilt from the jsDelivr CDN.

The generated `GitHub-2020.css` is **committed to the repository**, so the app
build does not depend on this tool. To refresh the style:

```bash
./generate.sh
```

then commit the updated `GitHub-2020.css`.

This replaces the original node-sass + `primer-markdown@4` pipeline, which no
longer builds on modern toolchains (node-sass is unsupported on current Node,
and `primer-markdown` has been unmaintained since ~2020). See `generate.sh`
for details, including how to bump the GitHub-style major version.
