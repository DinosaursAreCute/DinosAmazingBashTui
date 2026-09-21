{{#if logo}}
<div align="center">
<img src="{{logo}}" alt="{{name}}" width="560">
</div>

{{/if}}
{{heading}}

{{#if summary}}
{{summary}}

{{/if}}
{{#if news}}
<h2><img src="{{header_base}}/release-new.svg" alt="What's new" height="35"></h2>

{{news}}

{{/if}}
{{#if section:Added}}
<h2><img src="{{header_base}}/release-added.svg" alt="Added" height="35"></h2>

{{section:Added}}

{{/if}}
{{#if section:Changed}}
<h2><img src="{{header_base}}/release-changed.svg" alt="Changed" height="35"></h2>

{{section:Changed}}

{{/if}}
{{#if section:Deprecated}}
<h2><img src="{{header_base}}/release-deprecated.svg" alt="Deprecated" height="35"></h2>

{{section:Deprecated}}

{{/if}}
{{#if section:Removed}}
<h2><img src="{{header_base}}/release-removed.svg" alt="Removed" height="35"></h2>

{{section:Removed}}

{{/if}}
{{#if section:Fixed}}
<h2><img src="{{header_base}}/release-fixed.svg" alt="Fixed" height="35"></h2>

{{section:Fixed}}

{{/if}}
{{#if section:Security}}
<h2><img src="{{header_base}}/release-security.svg" alt="Security" height="35"></h2>

{{section:Security}}

{{/if}}
{{#if compare_url}}
**Full changelog:** {{compare_url}}

{{/if}}
<details><summary>Checksums (sha256)</summary>

```
{{checksums}}
```

</details>
