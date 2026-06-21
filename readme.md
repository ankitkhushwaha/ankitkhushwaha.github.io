# [Personal Blog](https://ankitkdev.com)

this blog use the [hugo-papermod](https://themes.gohugo.io/themes/hugo-papermod/) theme.
Apart from the native feature this themes has extra feature, such as:

- display code block through reading a file
- can add your timeline event, (example)[https://ankitkdev.com/klog]
- use custom css
- display output by compiled c code in about me page using webassembly
- githook to update `static/wasm/*.{js,wasm}` before commit
- has customized homepage
- can render the videoes from static/ folder

checkout related code under [layout/](https://github.com/ankitkhushwaha/ankitkhushwaha.github.io/tree/main/layouts/) dir.

This blog autodeploy the change to "github pages" using "github actions".

## To Add New Blog

```
hugo new blog/new-blog.md
```

this will create the blog under content/ dir.

## To Build the blog

For full rebuilds on change:
```
hugo server --disableFastRender
```

## Contribute

Contribution are welcome, Feel free to ask about the codebase, or specific decision that u didn't understand.

please raise your concern in [issue](https://github.com/ankitkhushwaha/ankitkhushwaha.github.io/issues) section.

Last Updated: June 21, 2026