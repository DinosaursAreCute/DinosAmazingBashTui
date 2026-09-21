# {{name}} {{version}}

{{#if news}}
## What's new

{{news}}

{{/if}}
{{#if section:Added}}
## Added

{{section:Added}}

{{/if}}
{{#if section:Changed}}
## Changed

{{section:Changed}}

{{/if}}
{{#if section:Fixed}}
## Fixed

{{section:Fixed}}

{{/if}}
{{#if compare_url}}
**Full changelog:** {{compare_url}}

{{/if}}
<details><summary>Checksums (sha256)</summary>

```
{{checksums}}
```

</details>
