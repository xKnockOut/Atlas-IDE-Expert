### Neu
- Updates an den Herausgeber gebunden (#1519): Jedes Release signiert die Versionsdatei mit einem eigenen Schlüssel (`atlas-version.json.sig`, ECDSA P-256, kein Code-Signing-Zertifikat nötig). AtlasUpdate prüft die Signatur, bevor es etwas lädt, auch vor dem Bau aus dem Quelltext, und bricht bei einer falschen Signatur ab. Fehlt sie (ältere Releases), weist Atlas beim fertig vorbereiteten Update darauf hin.

### Geändert
- Release ohne Code-Signing-Zertifikat: Die Release-Notizen sagen jetzt sichtbar, dass die Binärdateien nicht signiert sind und Updates über die signierte Versionsdatei geprüft werden. `Tools/Publish-ReleasePackage.ps1` braucht den Schlüssel für die Versionsdatei (`-SigningKey` oder `ATLAS_UPDATE_SIGNING_KEY`).
