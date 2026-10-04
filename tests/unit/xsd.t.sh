# xsd.t.sh - share/tui.xsd stays in step with the loader: every tag the loader registers is an element, every attribute it reads is
# declared somewhere, and (when xmllint is installed) every demo page validates.

_xsd_elements() { grep -oE '<xs:element name="[a-z_]+"' "$REPO/share/tui.xsd" | sed -E 's/.*"([a-z_]+)"/\1/' | sort -u; }
_xsd_attributes() { grep -oE '<xs:attribute name="[a-z_:0-9]+"' "$REPO/share/tui.xsd" | sed -E 's/.*"([a-z_:0-9]+)"/\1/' | sort -u; }

ti_xsd_declares_every_tag_the_loader_registers() {
	local missing
	missing="$(comm -23 <(grep -rhoE '^tui\.register tag [a-z_]+' "$REPO/lib" | awk '{print $3}' | sort -u) <(_xsd_elements) | tr '\n' ' ')"
	eq "" "$missing"
}

ti_xsd_declares_every_attribute_the_loader_reads() {
	local missing
	missing="$(comm -23 <(grep -rhoE '(attrv|attr_get) "\$[a-z0-9_]+" [a-z_0-9]+' "$REPO/lib" | awk '{print $3}' | grep -v '^__' | sort -u) <(_xsd_attributes) | tr '\n' ' ')"
	eq "" "$missing"
}

ti_xsd_has_no_required_pane_or_row_on_widgets() {
	# nested widgets get both from where they stand: a page written the v2 way must validate
	local n
	n="$(grep -cE 'name="(pane|row)" type="[a-z:]+" use="required"' "$REPO/share/tui.xsd")"
	eq 0 "$n"
}

ti_xsd_validates_the_demo_pages() {
	command -v xmllint >/dev/null || return 0
	local f bad=""
	for f in "$REPO"/share/demo/*.xml "$REPO"/share/defaults/pages/*.xml; do
		[[ "${f##*/}" == _[tk]* ]] && continue # template and key fragments are not documents
		xmllint --noout --schema "$REPO/share/tui.xsd" "$f" >/dev/null 2>&1 || bad+="${f##*/} "
	done
	eq "" "$bad"
}
