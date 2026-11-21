unit Atlas.Common.Updates.ManifestSignature;

// Platform-Feature "Updates" (#1519), Root: Echtheit der Versionsdatei. Der
// Release signiert atlas-version.json mit einem eigenen Schlüssel (ECDSA P-256
// über SHA-256, unabhängig von einem Code-Signing-Zertifikat) und legt die
// Signatur als <Versionsdatei>.sig daneben: 128 Hexziffern, r und s je 32
// Byte (Tools/Sign-VersionFile.ps1). Die öffentlichen Schlüssel stehen hier,
// zwei, damit ein neuer Schlüssel ausgeliefert werden kann, bevor der Release
// mit ihm signiert (Anlegen und Wechsel in docs/Release.md).
// Geprüft wird, bevor die Versionsdatei ausgewertet wird, also vor jedem
// Download und auch vor dem Bau aus dem Quelltext.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
{$SCOPEDENUMS ON}
  TUpdateManifestVerdict = (Genuine, Missing, Forged);
{$SCOPEDENUMS OFF}

  TUpdateManifestSignature = class
  public const
    /// <summary>Endung der Signaturdatei neben der Versionsdatei.</summary>
    cSuffix = '.sig';
    /// <summary>Fehlt die Signaturdatei, bricht die Vorbereitung ab (True) oder warnt nur (False). Zunächst nur
    /// warnend, weil Releases vor der Signatur keine Signaturdatei haben. Auf True setzen in der ersten Version,
    /// die erscheint, nachdem eine Version mit signierter Versionsdatei veröffentlicht ist: Deren Updater prüft
    /// dann jedes Update verbindlich.</summary>
    cRequired = False;
    /// <summary>Bytes eines öffentlichen Schlüssels (X und Y) und einer Signatur (r und s).</summary>
    cKeyBytes = 64;
    cSignatureBytes = 64;
  public
    /// <summary>Öffentliche Schlüssel, denen der Updater vertraut, je 128 Hexziffern.</summary>
    class function Keys: TArray<string>; static;
    /// <summary>Adresse der Signaturdatei zur Versionsdatei AManifestUrl.</summary>
    class function SignatureUrl(const AManifestUrl: string): string; static;
    /// <summary>Hexziffern in Bytes; False bei ungerader Länge oder anderen Zeichen. Leerraum am Rand zählt
    /// nicht (Zeilenende der Datei).</summary>
    class function TryHexBytes(const AText: string; out ABytes: TBytes): Boolean; static;
    /// <summary>Urteil über die Versionsdatei AManifest. AFound: Signaturdatei geladen, ASignature ihr Inhalt.
    /// Eine geladene, aber unlesbare oder nicht passende Signatur gilt als Fälschung.</summary>
    class function Verdict(const ATrust: IUpdateTrust; const AManifest: string; AFound: Boolean;
      const ASignature: string; const AKeys: TArray<string>): TUpdateManifestVerdict; static;
  end;

implementation

const
  /// <summary>Hauptschlüssel, mit dem der Release zurzeit signiert.</summary>
  cPrimaryKey = '';
  /// <summary>Reserveschlüssel für den Wechsel; sein privater Teil liegt getrennt vom Hauptschlüssel.</summary>
  cReserveKey = '';

{ TUpdateManifestSignature }

class function TUpdateManifestSignature.Keys: TArray<string>;
begin
  Result := TArray<string>.Create(cPrimaryKey, cReserveKey);
end;

class function TUpdateManifestSignature.SignatureUrl(const AManifestUrl: string): string;
begin
  Result := AManifestUrl + cSuffix;
end;

function HexValue(AChar: Char; out AValue: Byte): Boolean;
begin
  Result := True;
  case AChar of
    '0'..'9':
      AValue := Ord(AChar) - Ord('0');
    'a'..'f':
      AValue := Ord(AChar) - Ord('a') + 10;
    'A'..'F':
      AValue := Ord(AChar) - Ord('A') + 10;
  else
    AValue := 0;
    Result := False;
  end;
end;

class function TUpdateManifestSignature.TryHexBytes(const AText: string; out ABytes: TBytes): Boolean;
var
  mText: string;
  mIndex: Integer;
  mHigh, mLow: Byte;
begin
  ABytes := nil;
  mText := AText.Trim;
  Result := not Odd(Length(mText));
  if not Result then
  begin
    Exit;
  end;
  SetLength(ABytes, Length(mText) div 2);
  for mIndex := 0 to High(ABytes) do
  begin
    Result := HexValue(mText.Chars[2 * mIndex], mHigh) and HexValue(mText.Chars[2 * mIndex + 1], mLow);
    if not Result then
    begin
      ABytes := nil;
      Exit;
    end;
    ABytes[mIndex] := (mHigh shl 4) or mLow;
  end;
end;

class function TUpdateManifestSignature.Verdict(const ATrust: IUpdateTrust; const AManifest: string;
  AFound: Boolean; const ASignature: string; const AKeys: TArray<string>): TUpdateManifestVerdict;
var
  mSignature: TBytes;
begin
  if not AFound then
  begin
    Exit(TUpdateManifestVerdict.Missing);
  end;
  Result := TUpdateManifestVerdict.Forged;
  if TryHexBytes(ASignature, mSignature) and (Length(mSignature) = cSignatureBytes) and
    ATrust.ManifestIsGenuine(TEncoding.UTF8.GetBytes(AManifest), mSignature, AKeys) then
  begin
    Result := TUpdateManifestVerdict.Genuine;
  end;
end;

end.
