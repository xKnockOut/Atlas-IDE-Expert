### Neu
- Prüfregel `method-reference-called` (#1899): Eine Methodenreferenz in `Exit(ARef)` oder im Array-Literal neben `+` (`FHandlers + [AHandler]`) ruft Delphi auf, statt sie als Wert zu nehmen (wie E2035 bzw. E2010). Mit sicherer Korrektur für `Exit`: `Result := ARef; Exit;`.
