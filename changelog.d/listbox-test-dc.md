### Tests
- `TAtlasListBoxTests`: Der Bitmap-DC des Tests wurde während `WM_ERASEBKGND` von der VCL freigegeben (`FreeMemoryContexts` nach jeder Nachricht an die Liste), die Füllung ging ins Leere. Der Test sperrt die Leinwand jetzt während der Nachricht.
